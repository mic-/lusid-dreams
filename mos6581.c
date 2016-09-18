/*
 * Copyright 2013 Mic
 *
 * Licensed under the Apache License, Version 2.0 (the "License");
 * you may not use this file except in compliance with the License.
 * You may obtain a copy of the License at
 *
 *     http://www.apache.org/licenses/LICENSE-2.0
 *
 * Unless required by applicable law or agreed to in writing, software
 * distributed under the License is distributed on an "AS IS" BASIS,
 * WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
 * See the License for the specific language governing permissions and
 * limitations under the License.
 */

#include "mos6581.h"
#include <stdio.h>

#ifdef __32X__
#include "32x.h"
#endif

#define PAL_PHI 1000000
#define PLAYBACK_RATE 30000
#define EG_STEP_SHIFT 8
#define EG_STEP (((PAL_PHI<<EG_STEP_SHIFT)+(PLAYBACK_RATE/2))/PLAYBACK_RATE)
#define OSC_STEP_SHIFT 8
#define OSC_STEP (((PAL_PHI<<(OSC_STEP_SHIFT))+(PLAYBACK_RATE/2))/PLAYBACK_RATE)

static const uint32_t EG_PERIODS[] =
{
	9 << EG_STEP_SHIFT,
	32 << EG_STEP_SHIFT,
	63 << EG_STEP_SHIFT,
	95 << EG_STEP_SHIFT,
	149 << EG_STEP_SHIFT,
	220 << EG_STEP_SHIFT,
	267 << EG_STEP_SHIFT,
	313 << EG_STEP_SHIFT,
	392 << EG_STEP_SHIFT,
	977 << EG_STEP_SHIFT,
	1953 << EG_STEP_SHIFT,
	3125 << EG_STEP_SHIFT,
	3906 << EG_STEP_SHIFT,
	11718 << EG_STEP_SHIFT,
	19531 << EG_STEP_SHIFT,
	31250 << EG_STEP_SHIFT
};

struct mos6581 sidInstance;

static uint8_t prevRegValue;

static uint32_t noiseSeed = 1;


// Noise generation algorithm taken from SIDPlayer / (C) Christian Bauer
inline static uint8_t noise_rand()
{
	noiseSeed = noiseSeed * 1103515245 + 12345;
	return noiseSeed >> 16;
}

static void mos6581EnvelopeGenerator_reset(mos6581EnvelopeGenerator *eg)
{
	eg->phase = EG_ATTACK;
	eg->clocked = false;
	eg->out = 0;
	eg->clockDivider = 1;
	eg->pos = 0;
}

static void mos6581EnvelopeGenerator_step(mos6581EnvelopeGenerator *eg)
{
	if (eg->clocked) {
		eg->pos += EG_STEP;
		if (eg->pos >= eg->periodScaled) {
			eg->pos -= eg->periodScaled;
			switch (eg->phase) {
			case EG_ATTACK:
				eg->out++;
				if (eg->out >= 0xFF) {
					eg->out = 0xFF;
					eg->phase = EG_DECAY;
					eg->period = EG_PERIODS[eg->channel->chip->regs[eg->channel->regBlock + MOS6581_R_VOICE1_AD] & 0x0F];
					eg->clockDivider = 1;
					eg->periodScaled = eg->period;
				}
				break;

			case EG_DECAY:
				if (eg->out <= eg->sustainLevel) {
					eg->out = eg->sustainLevel;
					eg->clocked = false;
					eg->phase = EG_SUSTAIN;
				} else {
					if (eg->out) eg->out--;

					switch (eg->out) {
					case 0:
						eg->clockDivider = 1;
						eg->periodScaled = eg->period;
						break;
					case 6:
						eg->clockDivider = 30;
						eg->periodScaled = eg->period * 30;
						break;
					case 14:
						eg->clockDivider = 16;
						eg->periodScaled = eg->period * 16;
						break;
					case 26:
						eg->clockDivider = 8;
						eg->periodScaled = eg->period * 8;
						break;
					case 54:
						eg->clockDivider = 4;
						eg->periodScaled = eg->period * 4;
						break;
					case 93:
						eg->clockDivider = 2;
						eg->periodScaled = eg->period * 2;
						break;
					default:
						break;
					}
				}
				break;

			case EG_RELEASE:
				if (eg->out) {
					eg->out--;
					if (!eg->out) {
						eg->clocked = false;
					}
				}
				switch (eg->out) {
				case 0:
					eg->clockDivider = 1;
					eg->periodScaled = eg->period;
					break;
				case 6:
					eg->clockDivider = 30;
					eg->periodScaled = eg->period * 30;
					break;
				case 14:
					eg->clockDivider = 16;
					eg->periodScaled = eg->period * 16;
					break;
				case 26:
					eg->clockDivider = 8;
					eg->periodScaled = eg->period * 8;
					break;
				case 54:
					eg->clockDivider = 4;
					eg->periodScaled = eg->period * 4;
					break;
				case 93:
					eg->clockDivider = 2;
					eg->periodScaled = eg->period * 2;
					break;
				default:
					break;
				}
				break;

			default:
				break;
			}
		}
	}
}


void mos6581Channel_reset(struct mos6581Channel *chn)
{
	chn->eg.channel = chn;
	mos6581EnvelopeGenerator_reset(&(chn->eg));

	chn->period = 0;
	chn->step = 0;
	chn->duty = 0;
	chn->out = -1;
	chn->lfsr = 0x7FFFF8;
	noiseSeed = 1;
	chn->outputMask = 0xFFFF;
}


static void mos6581Channel_setIndex(struct mos6581Channel *chn, uint8_t idx)
{
	chn->index = idx;
	chn->prevIndex = (idx == 0) ? 2 : idx - 1;
	chn->nextIndex = (idx == 2) ? 0 : idx + 1;
	chn->regBlock = idx * 7;
	chn->nextRegBlock = chn->nextIndex * 7;
}


static void mos6581Channel_write(struct mos6581Channel *chn, uint32_t addr, uint8_t data)
{
	uint8_t reg = addr - MOS6581_REGISTER_BASE;
	uint8_t *regs = chn->chip->regs;
	uint64_t temp64;

	switch (reg) {
	case MOS6581_R_VOICE1_FREQ_LO:
	case MOS6581_R_VOICE2_FREQ_LO:
	case MOS6581_R_VOICE3_FREQ_LO:
		chn->step = data | ((uint16_t)regs[chn->regBlock + MOS6581_R_VOICE1_FREQ_HI] << 8);
		temp64 = chn->step;
		temp64 *= PAL_PHI << OSC_STEP_SHIFT;
		chn->stepScaled = temp64 / PLAYBACK_RATE;
		break;

	case MOS6581_R_VOICE1_FREQ_HI:
	case MOS6581_R_VOICE2_FREQ_HI:
	case MOS6581_R_VOICE3_FREQ_HI:
		chn->step = ((uint16_t)data << 8) | regs[chn->regBlock + MOS6581_R_VOICE1_FREQ_LO];
		temp64 = chn->step;
		temp64 *= PAL_PHI << OSC_STEP_SHIFT;
		chn->stepScaled = temp64 / PLAYBACK_RATE;
		break;

	case MOS6581_R_VOICE1_PW_LO:
	case MOS6581_R_VOICE2_PW_LO:
	case MOS6581_R_VOICE3_PW_LO:
		chn->duty = data | (((uint16_t)regs[chn->regBlock + MOS6581_R_VOICE1_PW_HI] & 0xF) << 8);
		break;

	case MOS6581_R_VOICE1_PW_HI:
	case MOS6581_R_VOICE2_PW_HI:
	case MOS6581_R_VOICE3_PW_HI:
		chn->duty = ((uint16_t)(data & 0xF) << 8) | regs[chn->regBlock + MOS6581_R_VOICE1_PW_LO];
		break;

	case MOS6581_R_VOICE1_AD:
	case MOS6581_R_VOICE2_AD:
	case MOS6581_R_VOICE3_AD:
		// Nothing special to do
		break;

	case MOS6581_R_VOICE1_SR:
	case MOS6581_R_VOICE2_SR:
	case MOS6581_R_VOICE3_SR:
		chn->eg.sustainLevel = regs[chn->regBlock + MOS6581_R_VOICE1_SR] >> 4;
		chn->eg.sustainLevel |= chn->eg.sustainLevel << 4;
		break;

	case MOS6581_R_VOICE1_CTRL:
	case MOS6581_R_VOICE2_CTRL:
	case MOS6581_R_VOICE3_CTRL:
		if ((data ^ prevRegValue) & MOS6581_VOICE_CTRL_GATE) {
			if (data & MOS6581_VOICE_CTRL_GATE) {
				chn->eg.phase = EG_ATTACK;
				chn->eg.clockDivider = 1;
				chn->eg.clocked = true;
				chn->eg.period = EG_PERIODS[regs[chn->regBlock + MOS6581_R_VOICE1_AD] >> 4];
			} else {
				chn->eg.phase = EG_RELEASE;
				chn->eg.period = EG_PERIODS[regs[chn->regBlock + MOS6581_R_VOICE1_SR] & 0x0F];
				chn->eg.clocked = true;
			}
			chn->eg.periodScaled = chn->eg.period * chn->eg.clockDivider;
		}
		if (data & MOS6581_VOICE_CTRL_TEST) {
			chn->lfsr = 0x7FFFF8;
			noiseSeed = 1;
			chn->pos = (0xFFFFFF << OSC_STEP_SHIFT);
		}
		break;

	default:
		break;
	}
}


void mos6581_reset()
{
	char *p;
	for (int i = 0; i < 3; i++) {
		sidInstance.channels[i].chip = &sidInstance;
		mos6581Channel_setIndex(&(sidInstance.channels[i]), i);
		mos6581Channel_reset(&(sidInstance.channels[i]));
	}
}


void mos6581_run(uint32_t numSamples, int16_t *buffer)
{
	static uint16_t noiseOut[3] = {0,0,0};
	struct mos6581Channel *chn;
	uint8_t *regs = sidInstance.regs;
	uint8_t ctrl, nextCtrl;
	uint16_t triOut, sawOut, pulseOut;
	uint32_t regBlock;
	uint32_t oldPos, step;
    uint32_t n;

    regBlock = 0;
	for (int i = 0; i < 3; i++) {
		chn = &(sidInstance.channels[i]);
		ctrl = regs[regBlock + MOS6581_R_VOICE1_CTRL];
  	    nextCtrl = regs[chn->nextRegBlock + MOS6581_R_VOICE1_CTRL];
  	    step = (ctrl & MOS6581_VOICE_CTRL_TEST) ? 0 : chn->stepScaled;
  	    n = numSamples;
        while (n--) {
            pulseOut = 0; sawOut = 0; triOut = 0;

			oldPos = chn->pos;
			chn->pos += step;

			// Hard sync
			if (nextCtrl & MOS6581_VOICE_CTRL_SYNC) {
				if ((chn->pos ^ oldPos) & chn->pos & (0x800000 << OSC_STEP_SHIFT)) {
					chn->chip->channels[chn->nextIndex].pos = 0;
				}
			}

			// Pulse wave
			if ((chn->pos >> (12 + OSC_STEP_SHIFT)) >= (0xFFF - chn->duty)) {
				pulseOut = 0xFFF;
			}

			// Triangle wave
			triOut = (chn->pos >> (11 + OSC_STEP_SHIFT)) & 0xFFE;
			if (ctrl & MOS6581_VOICE_CTRL_RMOD) {
				// Ring modulation
				if (chn->chip->channels[chn->prevIndex].pos & (0x800000 << OSC_STEP_SHIFT)) {
					triOut ^= 0xFFE;
				}
			} else if (chn->pos & (0x800000 << OSC_STEP_SHIFT)) {
				triOut ^= 0xFFE;
			}

			// Saw wave
			sawOut = chn->pos >> (12 + OSC_STEP_SHIFT);

			// Noise
			if ((chn->pos ^ oldPos) & (0xF00000 << OSC_STEP_SHIFT)) {
				noiseOut[i] = (uint16_t)noise_rand() << 4;
			}

			mos6581EnvelopeGenerator_step(&(chn->eg));

			uint32_t out = 0;
			if (ctrl & MOS6581_VOICE_CTRL_TRIANGLE) {
				out = triOut;
				if (ctrl & MOS6581_VOICE_CTRL_SAW) {
					out &= sawOut;
				}
				if (ctrl & MOS6581_VOICE_CTRL_PULSE) {
					out &= pulseOut;
				}
			} else if (ctrl & MOS6581_VOICE_CTRL_SAW) {
				out = sawOut;
				if (ctrl & MOS6581_VOICE_CTRL_PULSE) {
					out &= pulseOut;
				}
			} else if (ctrl & MOS6581_VOICE_CTRL_PULSE) {
				out = pulseOut;
			} else if (ctrl & MOS6581_VOICE_CTRL_NOISE) {
				out = noiseOut[i];
			}
			out *= chn->eg.out;
			*buffer++ = (out >> 8) & chn->outputMask;
		}
		regBlock += 7;
	}
}


void mos6581_write(uint32_t addr, uint8_t data)
{
	uint8_t reg = addr - MOS6581_REGISTER_BASE;

	prevRegValue = sidInstance.regs[reg];
	sidInstance.regs[reg] = data;

	if (reg >= MOS6581_R_VOICE1_FREQ_LO && reg <= MOS6581_R_VOICE1_SR) {
		mos6581Channel_write(&(sidInstance.channels[0]), addr, data);

	} else if (reg >= MOS6581_R_VOICE2_FREQ_LO && reg <= MOS6581_R_VOICE2_SR) {
		mos6581Channel_write(&(sidInstance.channels[1]), addr, data);

	} else if (reg >= MOS6581_R_VOICE3_FREQ_LO && reg <= MOS6581_R_VOICE3_SR) {
		mos6581Channel_write(&(sidInstance.channels[2]), addr, data);

	//} else if (MOS6581_R_FILTER_FC_LO == reg) {
	//} else if (MOS6581_R_FILTER_FC_HI == reg) {
	//} else if (MOS6581_R_FILTER_RESFIL == reg) {
		// Not handled

	} else if (MOS6581_R_FILTER_MODEVOL == reg) {
		if (data & 0x80) {
			sidInstance.channels[2].outputMask = 0;
		} else {
			sidInstance.channels[2].outputMask = 0xFFFF; //0xFFFFFF;
		}
	}
}


