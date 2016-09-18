/*
 * SID player for the 32X
 * Mic, 2016
 */

#include <sys/types.h>
#include <string.h>
#include <malloc.h>

#include "32x.h"
#include "hw_32x.h"
#include "sidplayer.h"
#include "sound.h"

// From songs/songs.s
extern const uint8_t *SONG_POINTERS[];
extern const size_t SONG_SIZES[];
extern const size_t NUM_SONGS;

// From gfx/gfx.s
extern const uint16_t PALETTE_DATA[];
extern const uint8_t BACKGROUND_GFX[];
extern const uint8_t SMALL_FONT[];
extern const uint8_t BIG_FONT[];
extern const uint8_t ARROWS[];
extern const uint8_t SMALL_DIGITS[];

const int BLINK_TABLE[] = {
4,4,4,5,5,5,6,6,6,6,7,7,7,8,8,8,8,9,9,9,9,10,10,10,10,10,10,10,10,10,10,10,10,10,10,10,
10,10,10,10,10,10,10,10,9,9,9,9,8,8,8,8,7,7,7,6,6,6,6,5,5,5,4,4,3,3,3,2,2,2,1,1,1,1,0,0,
0,-1,-1,-1,-1,-2,-2,-2,-2,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,-3,
-3,-3,-2,-2,-2,-2,-1,-1,-1,-1,0,0,0,1,1,1,1,2,2,2,3,3
};

const uint16_t DXDY_TABLE[] = {
0,384,192,128,96,76,64,54,48,42,38,34,32,29,27,25,24,22,21,20,19,18,17,16,16,15,14,14,13,13,12,12
};

int blinkStep = 0;

uint32_t mixFactor = 0, sampleBias = 0;

const psidFileHeader *sidHeader;
size_t currSong = 11, highlightedSong = 11, firstShownSong = 9;
volatile size_t *currSongCacheThrough = &currSong;
uint32_t subSong;
char digit[] = "00";

volatile uint16_t *frameBuffer16;
volatile uint16_t *cram16;
volatile uint16_t *overwriteImg16;

uint32_t milliSecondsPerTick = 50;	// 16.67 scaled by 3
uint32_t playTimeMs = 0;

int16_t *sampleBuffer = NULL;
volatile int16_t **sampleBufferCacheThrough;


/*
 * Put a string on the overwrite image using the small (8x8) font
 */
static void small_font_puts(const char *str, int x, int y)
{
	int c;
	uint8_t *fb8 = overwriteImg16 + 0x100;
	uint8_t pix;
	int screenOffs;
	int fontOffs;

	for (int i = 0; i < 22; i++) {
		c = str[i];
		if (!c) break;
		// Remap special characters
		else if (c=='Ö') c = '\\';
		else if (c=='ö') c = ']';
		else if (c=='ä') c = '[';
		else if (c=='ü') c = '_';
		else if (c=='á') c = 'a';
		else if (c=='é') c = 'e';

		c -= ' ';
		screenOffs = y*320 + i * 8 + x;
		// The font is a 128x48 pixel bitmap where each character is 8x8 pixels
		fontOffs = (c >> 4) << 10;
		fontOffs += (c & 15) << 3;
		for (int t = 0; t < 8; t++) {
			for (int s = 0; s < 8; s++) {
				pix = SMALL_FONT[fontOffs + s];
				if (pix) pix += 200;
				if (SMALL_FONT[fontOffs + s])
					fb8[screenOffs + s] = SMALL_FONT[fontOffs + s] + 200;
			}
			screenOffs += 320;
			fontOffs += 128;
		}
	}
}


/*
 * Put a string on the overwrite image using the big (16x16) font
 */
static void big_font_puts(const char *str, int x, int y, uint32_t baseCol)
{
	int c;
	uint8_t *fb8 = overwriteImg16 + 0x100;
	uint8_t pix;
	int screenOffs;
	int fontOffs;

	for (int i = 0; i < 16; i++) {
		c = str[i];
		if (!c) break;
		// Convert to upper case and remap special characters
		else if (c >= 'a' && c <= 'z') c -= ' ';
		else if (c == 'ä') c = ';';
		else if (c == 'á') c = 'A';

		c -= ' ';
		screenOffs = y*320 + i * 16 + x;
		// The font is a 256x64 pixel bitmap, where each character is 16x16 pixels
		fontOffs = (c >> 4) << 12;
		fontOffs += (c & 15) << 4;
		for (int t = 0; t < 16; t++) {
			for (int s = 0; s < 16; s++) {
				pix = BIG_FONT[fontOffs + s];
				if (pix) pix += baseCol;
				fb8[screenOffs + s] = pix;
			}
			screenOffs += 320;
			fontOffs += 256;
		}
	}
}


/*
 * Erase the previously drawn song info
 */
static void hide_song_info()
{
	int screenOffs = 0x100 + ((180*320 + 72) >> 1);
	uint16_t *p = &frameBuffer16[screenOffs];

	for (int i = 0; i < 32; i++) {
		memset(p, 0xC3, 22*8);	// 0xC3 is the background color for the song info box
		p += 160;
	}
}


/*
 * Refresh the song info "box" (title, author, copyright, sug-song)
 */
static void show_song_info()
{
	hide_song_info();

	small_font_puts(sidHeader->title, 72, 180);
	small_font_puts(sidHeader->author, 72, 188);
	small_font_puts(sidHeader->copyright, 72, 196);

	small_font_puts("Song:", 72, 204);

	int numSongsX = 136;
	if (subSong <= 9) {
		digit[0] = subSong + '0';
		digit[1] = 0;
		small_font_puts("/", 128, 204);
	} else {
		digit[0] = subSong / 10 + '0';
		digit[1] = subSong % 10 + '0';
		small_font_puts("/", 136, 204);
		numSongsX += 8;
	}
	small_font_puts(digit, 120, 204);

	if (sidHeader->numSongs <= 9) {
		digit[0] = sidHeader->numSongs + '0';
		digit[1] = 0;
	} else {
		digit[0] = sidHeader->numSongs / 10 + '0';
		digit[1] = sidHeader->numSongs % 10 + '0';
	}
	small_font_puts(digit, numSongsX, 204);
}


/*
 * Refresh the song list
 */
static void puts_active_list()
{
	psidFileHeader *hdr;
	int y = 48;

	// Erase the previously drawn list
	memcpy(frameBuffer16 + 0x100 + 48*160 + 16, BACKGROUND_GFX + 48*320 + 32, 96*320);

	for (int i = firstShownSong; i < firstShownSong+6; i++) {
		hdr = (psidFileHeader*)(SONG_POINTERS[i]);
		if (i == highlightedSong) {
			big_font_puts(hdr->title, 32, y, 202+9);
		} else {
			big_font_puts(hdr->title, 32, y, 202);
		}
		y += 16;
	}
}


static void draw_scroll_indicator(int x, int y, int which)
{
	uint8_t *fb8 = overwriteImg16 + 0x100;
	uint8_t *arrow = &ARROWS[which*16*9];

	fb8 += y*320 + x;

	for (int t = 0; t < 9; t++) {
		for (int s = 0; s < 15; s++) {
			uint8_t pix = *arrow++;
			if (pix) pix += 200+2+9+9;
			fb8[s] = pix;
		}
		arrow++;	// Each arrow is a 16x9 pixel bitmap
		fb8 += 320;
	}
}


/*
 * Draw the arrows that indicate whether the song list can be
 * scrolled further up/down
 */
static void update_scroll_indicators()
{
	if (firstShownSong != 0) {
		// Draw a green arrow
		draw_scroll_indicator(151, 35, 0);
	} else {
		// Draw a gray arrow
		draw_scroll_indicator(151, 35, 2);
	}

	if (firstShownSong != NUM_SONGS-6) {
		// Draw a green arrow
		draw_scroll_indicator(151, 150, 1);
	} else {
		// Draw a gray arrow
		draw_scroll_indicator(151, 150, 3);
	}
}


/*
 * Draw one of the small (5x6) digits used for displaying time
 */
static void draw_small_digit(int digit, int x, int y)
{
	uint8_t *fb8 = overwriteImg16 + 0x100;
	uint8_t *chr = &SMALL_DIGITS[digit*16*6];

	fb8 += y*320 + x;

	for (int t = 0; t < 6; t++) {
		for (int s = 0; s < 5; s++) {
			uint8_t pix = *chr++;
			if (pix) pix += 200+2+9+9+8;
			fb8[s] = pix;
		}
		chr += 11;
		fb8 += 320;
	}
}

/*
 * Show the current play time in "MM:SS"
 */
static void show_play_time()
{
	for (int i = 0; i < 6; i++) {
		memcpy(frameBuffer16 + 0x100 + (194+i)*160 + 6, BACKGROUND_GFX + (194+i)*320 + 12, 30);
	}

	uint32_t minutes = playTimeMs / (60000*3);
	if (minutes >= 100) {
		minutes = 0;
		playTimeMs = 0;
	}
	uint32_t seconds = (playTimeMs - minutes * (60000*3)) / (1000*3);

	draw_small_digit(minutes / 10, 12, 194);
	draw_small_digit(minutes % 10, 17, 194);

	draw_small_digit(10, 22, 194);	// 10 == colon

	draw_small_digit(seconds / 10, 27, 194);
	draw_small_digit(seconds % 10, 32, 194);
}


static void draw_line(int x1, int y1, int x2, int y2)
{
	int x, dy, dxdy, yStep, pixelCount;
	uint8_t *fb8 = overwriteImg16 + 0x100;

	dy = y2 - y1;
	if (!dy) {
		dy = 1;
		dxdy = 0x100;
	} else {
		if (dy < 0) dy = -dy;
		dxdy = DXDY_TABLE[dy];
	}

	x = x1 << 8;
	yStep = 320;
	if (y2 < y1) yStep = -320;
	else if (y2 == y1) yStep = 0;
	y1 *= 320;
	y2 *= 320;
	fb8 += y1;

	pixelCount = 0;
	for (;;) {
		fb8[x >> 8] = 201;
		pixelCount++;
		x += dxdy;
		fb8 += yStep;
		if (y1 == y2 && pixelCount >= 2) break;
		y1 += yStep;
	}

}


/*
 * Plot parts of the current sample buffer
 */
static void show_waveform()
{
	static uint16_t lastSample = 228-198;

	for (int i = 0; i < 34; i++) {
		memcpy(frameBuffer16 + 0x100 + (180+i)*160 + 137, BACKGROUND_GFX + (180+i)*320 + 274, 40);
	}

	int offs = 0;
	int x = 276;
	if (*sampleBufferCacheThrough) {
		for (int i = 0; i < 19; i++) {
			uint16_t smp = ((*sampleBufferCacheThrough)[offs]);
			smp = (smp>>5) + (smp>>6);
			offs += 25;
			draw_line(x, 213-lastSample, x+2, 213-smp);
			lastSample = smp;
			x += 2;
		}
	}
}


/*
 * Update both framebuffers
 */
static void update_screen()
{
	Hw32xScreenFlip(1);
	puts_active_list();
	show_song_info();
	update_scroll_indicators();

	Hw32xScreenFlip(1);
	puts_active_list();
	show_song_info();
	update_scroll_indicators();
}


/*
 * Start playback of a new song
 */
static void new_song(int index)
{
    // lock the mixer while killing the old music
    LockMixer(MIXER_LOCK_MSH2);

    UnlockMixer();

    Hw32xDelay(1); // allow the mixer to see the music is dead

    // lock the mixer while starting the new music
    LockMixer(MIXER_LOCK_MSH2);

	*currSongCacheThrough = index;
	playTimeMs = 0;

    UnlockMixer();

	sidHeader = sidPlayer_getFileHeader();
	subSong = sidHeader->firstSong;

    update_screen();
}



/*
 * Move to the next entry in the song list
 */
static void move_to_next_list_item()
{
	if (highlightedSong < (NUM_SONGS - 1)) {
		highlightedSong++;
		blinkStep = 0;
	}

	// Check if the song list needs to be scrolled
	if ( ((highlightedSong - firstShownSong) >= ((6 >> 1) + 1)) &&
		 (firstShownSong  < (NUM_SONGS - 6)) )
		firstShownSong++;

	update_screen();
}


/*
 * Move to the previous entry in the song list
 */
static void move_to_previous_list_item()
{
	if (highlightedSong > 0) {
		highlightedSong--;
		blinkStep = 0;
	}

	// Check if the song list needs to be scrolled
	if ( (firstShownSong > highlightedSong) ||
		 ((firstShownSong) &&
		 ((highlightedSong - firstShownSong) < (6 >> 1))) )
		firstShownSong--;

	update_screen();
}


/*
 * Apply a blinking effect on the highlighted song (offset R, G and B by a sine wave)
 */
void blink()
{
	for (int i = 0; i < 9; i++) {
		if (i != 1) {					// the second color in this sub-palette is the black text shade
			uint32_t col = PALETTE_DATA[211 + i];	// colors 211..219 are used for the highlighted song name
			int r = col & 0x1F;
			int g = (col >> 5) & 0x1F;
			int b = (col >> 10) & 0x1F;
			int r2 = r + BLINK_TABLE[blinkStep];
			int g2 = g + BLINK_TABLE[blinkStep];
			int b2 = b + BLINK_TABLE[blinkStep];
			if (r2 > 31) r2 = 31; else if (r2 < 0) r2 = 0;
			if (g2 > 31) g2 = 31; else if (g2 < 0) g2 = 0;
			if (b2 > 31) b2 = 31; else if (b2 < 0) b2 = 0;
			cram16[211 + i] = COLOR(r2, g2, b2);
		}
	}

	blinkStep += 3;
	if (blinkStep >= 128)
		blinkStep -= 128;
}


int main( void )
{
    unsigned short new_buttons, curr_buttons;
    unsigned short buttons = 0, paused = 0;
	unsigned short up_delay, down_delay;

	currSongCacheThrough = (volatile size_t*)((uint32_t)&currSong | 0x20000000);
	sampleBufferCacheThrough = (volatile int16_t**)((uint32_t)&sampleBuffer | 0x20000000);

    Hw32xInit(MARS_VDP_MODE_256);

	frameBuffer16 = &MARS_FRAMEBUFFER;
	overwriteImg16 = &MARS_OVERWRITE_IMG;
	cram16 = &MARS_CRAM;

	for (int i = 0; i < 200+2+9+9+8+2; i++)	{
		cram16[i] = PALETTE_DATA[i] & 0x7FFF;
	}
	cram16[201] = 0;	// Set the C64 font color to black


	Hw32xScreenFlip(1);
	memcpy(frameBuffer16 + 0x100, BACKGROUND_GFX, 320*224);
	Hw32xScreenFlip(1);
	memcpy(frameBuffer16 + 0x100, BACKGROUND_GFX, 320*224);
	small_font_puts("Loading...", 72, 180);
	Hw32xScreenFlip(1);

    while (MARS_SYS_COMM6 != MIXER_UNLOCKED) ; // wait for sound subsystem to init

	// Calculate the mixing factor used for converting 3 x 12-bit samples
	// to a 10-bit sample.
	if (MARS_VDP_DISPMODE & MARS_NTSC_FORMAT) {
		// NTSC
		mixFactor = ((23011361 * 3 / SAMPLE_RATE) << 16) / (0xFFF*3 * 0xF * 9);
		sampleBias = (23011361 / (SAMPLE_RATE * 3));
	} else {
		// PAL
		mixFactor = ((22801467 * 3 / SAMPLE_RATE) << 16) / (0xFFF*3 * 0xF * 9);
		sampleBias = (22801467 / (SAMPLE_RATE * 3));
		milliSecondsPerTick = 60;	// 20 scaled by 3
	}

	new_song(currSong);

	up_delay = 60;
	down_delay = 60;

    while (1)
    {
        Hw32xDelay(2);

		blink();

		playTimeMs += milliSecondsPerTick << 1;
		show_play_time();
		show_waveform();
		Hw32xScreenFlip(1);

        // MARS_SYS_COMM10 holds the current button values: - - - - M X Y Z S A C B R L D U
        curr_buttons = MARS_SYS_COMM8;
        if ((curr_buttons & SEGA_CTRL_TYPE) == SEGA_CTRL_NONE)
            curr_buttons = MARS_SYS_COMM10; // if no pad 1, try using pad 2

        new_buttons = curr_buttons ^ buttons; // set if button changed

        if (new_buttons & SEGA_CTRL_START) {
            if (!(curr_buttons & SEGA_CTRL_START)) {
                // START just released
                if (paused) {
                } else {
                }
            }
        }

        if (new_buttons & SEGA_CTRL_B) {
            if (!(curr_buttons & SEGA_CTRL_B)) {
				currSong = highlightedSong;
              	new_song(currSong);
 			}
		}

        if (new_buttons & SEGA_CTRL_DOWN) {
            if (!(curr_buttons & SEGA_CTRL_DOWN)) {
                // DOWN just released
                move_to_next_list_item();
            } else {
				// DOWN just pressed
				down_delay = 28;
			}
        } else if (curr_buttons & buttons & SEGA_CTRL_DOWN) {
			if (0 == --down_delay) {
				move_to_next_list_item();
				down_delay = 9;
			}
		}


        if (new_buttons & SEGA_CTRL_UP) {
            if (!(curr_buttons & SEGA_CTRL_UP)) {
                // UP just released
                move_to_previous_list_item();
			} else {
				// UP just pressed
				up_delay = 28;
			}
		} else if (curr_buttons & buttons & SEGA_CTRL_UP) {
			if (0 == --up_delay) {
				move_to_previous_list_item();
				up_delay = 9;
			}
        }

        if (new_buttons & SEGA_CTRL_RIGHT) {
            if (!(curr_buttons & SEGA_CTRL_RIGHT)) {
                // RIGHT just released
                LockMixer(MIXER_LOCK_MSH2);
                subSong++;
                if (subSong > sidHeader->numSongs)
                	subSong = 1;
                sidPlayer_setSubSong(subSong - 1);
                playTimeMs = 0;
                UnlockMixer();
                update_screen();
            }
        }

        if (new_buttons & SEGA_CTRL_LEFT) {
            if (!(curr_buttons & SEGA_CTRL_LEFT)) {
                // LEFT just released
                LockMixer(MIXER_LOCK_MSH2);
                if (subSong > 1)
                	subSong--;
                else
                	subSong = sidHeader->numSongs;
                sidPlayer_setSubSong(subSong - 1);
                playTimeMs = 0;
                UnlockMixer();
                update_screen();
            }
        }

        buttons = curr_buttons;
    }

    LockMixer(MIXER_LOCK_MSH2); // locked - stop playing

    return 0;
}

