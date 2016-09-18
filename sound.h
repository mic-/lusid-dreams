#ifndef SOUND_H
#define SOUND_H

#include <stdint.h>

#define SAMPLE_RATE    30000
#define SAMPLE_MIN         2
#define SAMPLE_CENTER    380
#define SAMPLE_MAX      760

/*
#define SAMPLE_RATE    24000
#define SAMPLE_MIN         2
#define SAMPLE_CENTER    479
#define SAMPLE_MAX      958
*/


#define MAX_NUM_SAMPLES 1024

extern uint16_t num_samples;
extern int16_t snd_buffer[];

extern void fill_buffer(int16_t *buffer);

#endif
