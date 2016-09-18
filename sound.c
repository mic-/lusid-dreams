#include <string.h>
#include "sidplayer.h"

#define NUM_SAMPLES (SAMPLE_RATE/50)

#include "32x.h"
#include "sound.h"

// From songs/songs.s
extern const uint8_t *SONG_POINTERS[];
extern const size_t SONG_SIZES[];

int16_t __attribute__((aligned(16))) snd_buffer[MAX_NUM_SAMPLES*2*2];
int16_t __attribute__((aligned(16))) temp_buffer[NUM_SAMPLES*3];

uint16_t num_samples = NUM_SAMPLES;

extern int8_t mvolume;
size_t slaveCurrSong = 0;
extern volatile size_t *currSongCacheThrough;
extern volatile int16_t **sampleBufferCacheThrough;

// From mixer.s
extern void MixSidVoices(int16_t *filtered, int16_t *src, uint32_t count);


void fill_buffer(int16_t *buffer)
{
	num_samples = NUM_SAMPLES;

    LockMixer(MIXER_LOCK_SSH2);
    if (slaveCurrSong != *currSongCacheThrough) {
		slaveCurrSong = *currSongCacheThrough;
	    sidPlayer_prepare(SONG_POINTERS[slaveCurrSong], SONG_SIZES[slaveCurrSong]);
	}
    sidPlayer_run(NUM_SAMPLES, temp_buffer);
    *sampleBufferCacheThrough = buffer;
    UnlockMixer();

	// Mix the the 3 SID voices into a single mono buffer and apply a low-pass filter
	MixSidVoices(buffer, temp_buffer, NUM_SAMPLES);
}

