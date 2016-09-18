/*
 * Licensed under the BSD license
 *
 * debug_32x.c - Debug screen functions.
 *
 * Copyright (c) 2005 Marcus R. Brown <mrbrown@ocgnet.org>
 * Copyright (c) 2005 James Forshaw <tyranid@gmail.com>
 * Copyright (c) 2005 John Kelley <ps2dev@kelley.ca>
 *
 * Altered for 32X by Chilly Willy
 */

#include "32x.h"
#include "sound.h"

#include <stdarg.h>
#include <stdio.h>
#include <string.h>

static int32_t X = 0, Y = 0;
static int32_t MX = 40, MY = 25;
static int32_t init = 0;
static uint16_t fgc = 0, bgc = 0;
static uint8_t fgs = 0, bgs = 0;

/*static*/ uint16_t currentFB = 0;

void Hw32xSetFGColor(int32_t s, int32_t r, int32_t g, int32_t b)
{
    volatile uint16_t *palette = &MARS_CRAM;
    fgs = s;
    fgc = COLOR(r, g, b);
    palette[fgs] = fgc;
}

void Hw32xSetBGColor(int32_t s, int32_t r, int32_t g, int32_t b)
{
    volatile uint16_t *palette = &MARS_CRAM;
    bgs = s;
    bgc = COLOR(r, g, b);
    palette[bgs] = bgc;
}

void Hw32xInit(int32_t vmode)
{
    volatile uint16_t *frameBuffer16 = &MARS_FRAMEBUFFER;
    int32_t i;

    // Wait for the SH2 to gain access to the VDP
    while ((MARS_SYS_INTMSK & MARS_SH2_ACCESS_VDP) == 0) ;

    if (vmode == MARS_VDP_MODE_256)
    {
        // Set 8-bit paletted mode, 224 lines
        MARS_VDP_DISPMODE = MARS_224_LINES | MARS_VDP_MODE_256;

        // init both framebuffers

        // Flip the framebuffer selection bit and wait for it to take effect
        MARS_VDP_FBCTL = currentFB ^ 1;
        while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
        currentFB ^= 1;
        // rewrite line table
        for (i=0; i<224; i++)
            frameBuffer16[i] = i*160 + 0x100; /* word offset of line */
        // clear screen
        for (i=0x100; i<0x10000; i++)
            frameBuffer16[i] = 0;

        // Flip the framebuffer selection bit and wait for it to take effect
        MARS_VDP_FBCTL = currentFB ^ 1;
        while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
        currentFB ^= 1;
        // rewrite line table
        for (i=0; i<224; i++)
            frameBuffer16[i] = i*160 + 0x100; /* word offset of line */
        // clear screen
        for (i=0x100; i<0x10000; i++)
            frameBuffer16[i] = 0;

        MX = 40;
        MY = 28;
    }
    else if (vmode == MARS_VDP_MODE_32K)
    {
        // Set 16-bit direct mode, 224 lines
        MARS_VDP_DISPMODE = MARS_224_LINES | MARS_VDP_MODE_32K;

        // init both framebuffers

        // Flip the framebuffer selection bit and wait for it to take effect
        MARS_VDP_FBCTL = currentFB ^ 1;
        while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
        currentFB ^= 1;
        // rewrite line table
        for (i=0; i<200; i++)
            frameBuffer16[i] = i*320 + 0x100; /* word offset of line */
        for (i=201; i<224; i++)
            frameBuffer16[i] = 201*320 + 0x100; /* word offset of line */
        // clear screen
        for (i=0x100; i<0x10000; i++)
            frameBuffer16[i] = 0;

        // Flip the framebuffer selection bit and wait for it to take effect
        MARS_VDP_FBCTL = currentFB ^ 1;
        while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
        currentFB ^= 1;
        // rewrite line table
        for (i=0; i<200; i++)
            frameBuffer16[i] = i*320 + 0x100; /* word offset of line */
        for (i=201; i<224; i++)
            frameBuffer16[i] = 201*320 + 0x100; /* word offset of line */
        // clear screen
        for (i=0x100; i<0x10000; i++)
            frameBuffer16[i] = 0;

        MX = 40;
        MY = 25;
    }

    Hw32xSetFGColor(255,31,31,31);
    Hw32xSetBGColor(0,0,0,0); /* transparent */
    X = Y = 0;
    init = vmode;
}

int32_t Hw32xScreenGetX()
{
    return X;
}

int32_t Hw32xScreenGetY()
{
    return Y;
}

void Hw32xScreenSetXY(int32_t x, int32_t y)
{
    if( x<MX && x>=0 )
        X = x;
    if( y<MY && y>=0 )
        Y = y;
}

void Hw32xScreenClear()
{
    int32_t i;
    int32_t l = (init == MARS_VDP_MODE_256) ? 320*224/2 + 0x100 : 320*200 + 0x100;
    volatile uint16_t *frameBuffer16 = &MARS_FRAMEBUFFER;

    // clear screen
    for (i=0x100; i<l; i++)
        frameBuffer16[i] = 0;

    // Flip the framebuffer selection bit and wait for it to take effect
    MARS_VDP_FBCTL = currentFB ^ 1;
    while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
    currentFB ^= 1;

    // clear screen
    for (i=0x100; i<l; i++)
        frameBuffer16[i] = 0;

    Hw32xSetFGColor(255,31,31,31);
    Hw32xSetBGColor(0,0,0,0);
    X = Y = 0;
}

extern uint8_t msx[];

static void debug_put_char_16(int32_t x, int32_t y, uint8_t ch)
{
    volatile uint16_t *fb = &MARS_FRAMEBUFFER;
    int32_t i,j;
    uint8_t *font;
    int32_t vram, vram_ptr;

    if(!init)
    {
        return;
    }

    vram = 0x100 + x * 8;
    vram += (y * 8 * 320);

    font = &msx[ (int32_t)ch * 8];

    for (i=0; i<8; i++, font++)
    {
        vram_ptr  = vram;
        for (j=0; j<8; j++)
        {
            if ((*font & (128 >> j)))
                fb[vram_ptr] = fgc;
            else
                fb[vram_ptr] = bgc;
            vram_ptr++;
        }
        vram += 320;
    }
}

static void debug_put_char_8(int32_t x, int32_t y, uint8_t ch)
{
    volatile uint8_t *fb = (volatile uint8_t *)&MARS_FRAMEBUFFER;
    int32_t i,j;
    uint8_t *font;
    int32_t vram, vram_ptr;

    if(!init)
    {
        return;
    }

    vram = 0x200 + x * 8;
    vram += (y * 8 * 320);

    font = &msx[ (int32_t)ch * 8];

    for (i=0; i<8; i++, font++)
    {
        vram_ptr  = vram;
        for (j=0; j<8; j++)
        {
            if ((*font & (128 >> j)))
                fb[vram_ptr] = fgs;
            else
                fb[vram_ptr] = bgs;
            vram_ptr++;
        }
        vram += 320;
    }
}

void Hw32xScreenPutChar(int32_t x, int32_t y, uint8_t ch)
{
    if (init == MARS_VDP_MODE_256)
    {
        debug_put_char_8(x, y, ch);
    }
    else if (init == MARS_VDP_MODE_32K)
    {
        debug_put_char_16(x, y, ch);
    }
}

void Hw32xScreenClearLine(int32_t Y)
{
    int32_t i;

    for (i=0; i < MX; i++)
    {
        Hw32xScreenPutChar(i, Y, ' ');
    }
}

/* Print non-nul terminated strings */
int32_t Hw32xScreenPrintData(const char *buff, int32_t size)
{
    int32_t i;
    char c;

    if(!init)
    {
        return 0;
    }

    for (i = 0; i<size; i++)
    {
        c = buff[i];
        switch (c)
        {
            case '\r':
                X = 0;
                break;
            case '\n':
                X = 0;
                Y++;
                if (Y >= MY)
                    Y = 0;
                Hw32xScreenClearLine(Y);
                break;
            case '\t':
                X = (X + 4) & ~3;
                if (X >= MX)
                {
                    X = 0;
                    Y++;
                    if (Y >= MY)
                        Y = 0;
                    Hw32xScreenClearLine(Y);
                }
                break;
            default:
                Hw32xScreenPutChar(X, Y, c);
                X++;
                if (X >= MX)
                {
                    X = 0;
                    Y++;
                    if (Y >= MY)
                        Y = 0;
                    Hw32xScreenClearLine(Y);
                }
        }
    }

    return i;
}

int32_t Hw32xScreenPuts(const char *str)
{
    int32_t ret;

    // Flip the framebuffer selection bit and wait for it to take effect
    MARS_VDP_FBCTL = currentFB ^ 1;
    while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
    currentFB ^= 1;

    ret = Hw32xScreenPrintData(str, strlen(str));

    // Flip the framebuffer selection bit and wait for it to take effect
    MARS_VDP_FBCTL = currentFB ^ 1;
    while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
    currentFB ^= 1;

    return ret;
}

void Hw32xScreenPrintf(const char *format, ...)
{
   va_list  opt;
   char     buff[256];

   va_start(opt, format);
   vsnprintf(buff, (size_t)sizeof(buff), format, opt);
   va_end(opt);
   Hw32xScreenPuts(buff);
}

void Hw32xDelay(int32_t ticks)
{
    uint32_t ct = MARS_SYS_COMM12 + ticks;
    while (MARS_SYS_COMM12 < ct) ;
}

void Hw32xScreenFlip(int32_t wait)
{
    // Flip the framebuffer selection bit
    MARS_VDP_FBCTL = currentFB ^ 1;
    if (wait)
    {
        while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
        currentFB ^= 1;
    }
}

void Hw32xFlipWait()
{
    while ((MARS_VDP_FBCTL & MARS_VDP_FS) == currentFB) ;
    currentFB ^= 1;
}


void slave_dma1_handler(void)
{
    static int32_t which = 0;

    while (MARS_SYS_COMM6 == MIXER_LOCK_MSH2) ; // locked by MSH2

    SH2_DMA_CHCR1; // read TE
    SH2_DMA_CHCR1 = 0; // clear TE

    if (which)
    {
        // start DMA on first buffer and fill second
        SH2_DMA_SAR1 = ((uint32_t)&snd_buffer[0]) | 0x20000000;
        SH2_DMA_TCR1 = num_samples; // number of shorts
        SH2_DMA_CHCR1 = 0x14E5; // dest fixed, src incr, size short, ext req, dack mem to dev, dack hi, dack edge, dreq rising edge, cycle-steal, dual addr, intr enabled, clear TE, dma enabled

        fill_buffer(&snd_buffer[MAX_NUM_SAMPLES * 2]);
    }
    else
    {
        // start DMA on second buffer and fill first
        SH2_DMA_SAR1 = ((uint32_t)&snd_buffer[MAX_NUM_SAMPLES * 2]) | 0x20000000;
        SH2_DMA_TCR1 = num_samples; // number of shorts
        SH2_DMA_CHCR1 = 0x14E5; // dest fixed, src incr, size short, ext req, dack mem to dev, dack hi, dack edge, dreq rising edge, cycle-steal, dual addr, intr enabled, clear TE, dma enabled

        fill_buffer(&snd_buffer[0]);
    }

    which ^= 1; // flip audio buffer
}

void slave(void)
{
    uint16_t sample, ix;

    // init DMA
    SH2_DMA_SAR0 = 0;
    SH2_DMA_DAR0 = 0;
    SH2_DMA_TCR0 = 0;
    SH2_DMA_CHCR0 = 0;
    SH2_DMA_DRCR0 = 0;
    SH2_DMA_SAR1 = 0;
    SH2_DMA_DAR1 = 0x20004038; 	// Set the PWM mono output as the destination
    SH2_DMA_TCR1 = 0;
    SH2_DMA_CHCR1 = 0;
    SH2_DMA_DRCR1 = 0;
    SH2_DMA_DMAOR = 1; // enable DMA

    SH2_DMA_VCR1 = 72; // set exception vector for DMA channel 1
    SH2_INT_IPRA = (SH2_INT_IPRA & 0xF0FF) | 0x0F00; // set DMA INT to priority 15

    // init the sound hardware
    MARS_PWM_MONO = 1;
    MARS_PWM_MONO = 1;
    MARS_PWM_MONO = 1;
    if (MARS_VDP_DISPMODE & MARS_NTSC_FORMAT)
        MARS_PWM_CYCLE = (((23011361 << 1)/SAMPLE_RATE + 1) >> 1) + 1; // for NTSC clock
    else
        MARS_PWM_CYCLE = (((22801467 << 1)/SAMPLE_RATE + 1) >> 1) + 1; // for PAL clock
    MARS_PWM_CTRL = 0x0185; // TM = 1, RTP, RMD = right, LMD = left

    sample = SAMPLE_MIN;
    /* ramp up to SAMPLE_CENTER to avoid click in audio (real 32X) */
    while (sample < SAMPLE_CENTER)
    {
        for (ix=0; ix<(SAMPLE_RATE*2)/(SAMPLE_CENTER - SAMPLE_MIN); ix++)
        {
            while (MARS_PWM_MONO & 0x8000) ; // wait while full
            MARS_PWM_MONO = sample;
        }
        sample++;
    }

    // initialize mixer
    MARS_SYS_COMM6 = MIXER_UNLOCKED; // sound subsystem running
    fill_buffer(&snd_buffer[0]); // fill first buffer
    slave_dma1_handler(); // start DMA

    SetSH2SR(2);
    while (1)
    {
        if (MARS_SYS_COMM4 == SSH2_WAITING)
            continue; // wait for command

        // do command in COMM4

        // done
        MARS_SYS_COMM4 = SSH2_WAITING;
    }
}
