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

#include <string.h>
#include <stddef.h>
#include "sidmapper.h"
#include "sidplayer.h"
#include "mos6581.h"

#ifdef __32X__
#include "32x.h"
#endif

uint8_t RAM[64 * 1024];



void sidMapper_writeByte(uint16_t addr, uint8_t data)
{
	uint8_t bankSelect = RAM[1] & 7;

	switch (addr >> 12) {
	case 0xA: case 0xB:
		if ((bankSelect & 3) != 3) {
			RAM[addr] = data;
		}
		break;
	case 0xD:
		if (bankSelect >= 5) {
			// I/O at D000-DFFF
			if (addr >= MOS6581_REGISTER_BASE && addr <= MOS6581_REGISTER_BASE + 0x3FF) {
				addr &= (MOS6581_REGISTER_BASE + 0x1F);
				mos6581_write(addr, data);
				if (addr == MOS6581_REGISTER_BASE + MOS6581_R_FILTER_MODEVOL) {
					sidPlayer_setMasterVolume(data & 0x0F);
				}
			}
		} else if (bankSelect == 4 || bankSelect == 0) {
			// RAM at D000-DFFF
			RAM[addr] = data;
		} /*else {
			//NLOGD("SidMapper", "D000-DFFF mapped to ROM");
		}*/
		break;
	case 0xE: case 0xF:
		if ((bankSelect & 3) < 2) {
			RAM[addr] = data;
		}
		break;
	default:
		RAM[addr] = data;
		break;
	}

}


void sidMapper_reset()
{
	RAM[1] = 0x36; //0x37;

#ifdef __32X__
	CacheClearLine(RAM);
#endif
}

