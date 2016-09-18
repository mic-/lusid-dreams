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

#define NLOG_LEVEL_ERROR 0

#include <string.h>
#include <stdio.h>
#include "sidplayer.h"
#include "emu6502.h"

#ifdef __32X__
#include "32x.h"
#endif

#define BYTESWAP(w) w = (((w) & 0xFF00) >> 8) | (((w) & 0x00FF) << 8)
#define WORDSWAP(d) d = (((d) & 0xFFFF0000) >> 16) | (((d) & 0x0000FFFF) << 16)

psidFileHeader fileHeader;
static bool prepared = false;

int masterVolume;

void sidPlayer_reset()
{
}


void sidPlayer_prepare(uint8_t *buffer, size_t bufLen)
{
    uint16_t *p16;

	prepared = false;

	memset(RAM, 0, 65536);
    memcpy((char*)&fileHeader, buffer, 0x76);
    buffer += 0x76;
    bufLen -= 0x76;

#ifndef __32X__
	BYTESWAP(fileHeader.version);
	BYTESWAP(fileHeader.dataOffset);
	BYTESWAP(fileHeader.loadAddress);
	BYTESWAP(fileHeader.initAddress);
	BYTESWAP(fileHeader.playAddress);
	BYTESWAP(fileHeader.numSongs);
	BYTESWAP(fileHeader.firstSong);

	p16 = (uint16_t*)&fileHeader.speed;
	BYTESWAP(*p16);
	p16++;
	BYTESWAP(*p16);
	WORDSWAP(fileHeader.speed);
#endif

	if (fileHeader.version == 2) {
        memcpy(&fileHeader.flags, buffer, sizeof(fileHeader) - 0x76);
        buffer += sizeof(fileHeader) - 0x76;
        bufLen -= sizeof(fileHeader) - 0x76;
	}

	if (fileHeader.loadAddress == 0) {
		// First two bytes of data contain the load address
		memcpy(&fileHeader.loadAddress, buffer, 2);
		BYTESWAP(fileHeader.loadAddress);
		buffer += 2;
		bufLen -= 2;
	} else {
		//printf("LOAD: %#x", mFileHeader.loadAddress);
	}

    memcpy(&RAM[fileHeader.loadAddress], buffer, bufLen);

    if (!fileHeader.initAddress) fileHeader.initAddress = fileHeader.loadAddress;

	sidPlayer_setMasterVolume(0);

	sidMapper_reset();
	emu6502_reset();
	mos6581_reset();

	regS = 0xFF;
	prepared = true;
	sidPlayer_setSubSong(fileHeader.firstSong - 1);
}


void sidPlayer_setMasterVolume(int masterVol)
{
	masterVolume = masterVol;
}

const unsigned char TEST_CODE[] = {
	0x38,				// SEC
	0x5E, 0x11,0xFF,	// LSR $FF11,X
	0x4C, 0x17,0x04		// JMP -
};

static void __attribute__ ((noinline)) sidPlayer_execute6502(uint16_t address, uint32_t numCycles)
{
	// Note: this is crap, but it happens to work for some tunes.
	if (address) {
		// JSR loadAddress
		RAM[0x413] = 0x20;
		RAM[0x414] = address & 0xff;
		RAM[0x415] = address >> 8;
		// -: JMP -
		RAM[0x416] = 0x4c;
		RAM[0x417] = 0x16;
		RAM[0x418] = 0x04;
/*	memcpy(&RAM[0x413], TEST_CODE, 16);
	RAM[0x10] = 0x70;
	regX = 0xFF;
	regA = 0xE0;*/

		regPC = 0x413;
		cpuCycles = 0;
		emu6502_run(numCycles);
	} else {
		uint8_t bankSelect = RAM[0x01] & 3;
		if (bankSelect >= 2) {
			emu6502_setBrkVector(0x314);
		}
		// BRK
		RAM[0x9ff0] = 0x00;
		// -: JMP -
		RAM[0x9ff1] = 0x4c;
		RAM[0x9ff2] = 0xf1;
		RAM[0x9ff3] = 0x9f;
		regPC = 0x9ff0;
		cpuCycles = 0;
		emu6502_run(numCycles);
		emu6502_setBrkVector(0xfffe);
	}
}

void __attribute__ ((noinline)) sidPlayer_setSubSong(uint32_t subSong)
{
	regA = subSong;
	sidPlayer_execute6502(fileHeader.initAddress, 1500000);
}


void __attribute__ ((noinline)) sidPlayer_run(uint32_t numSamples, int16_t *buffer)
{

	sidPlayer_execute6502(fileHeader.playAddress, 20000);
	mos6581_run(numSamples, buffer);
}


const psidFileHeader *sidPlayer_getFileHeader()
{
    return (const psidFileHeader*)&fileHeader;
}

const char *sidPlayer_getTitle()
{
    return (const char*)(fileHeader.title);
}

const char *sidPlayer_getAuthor()
{
    return (const char*)(fileHeader.author);
}

const char *sidPlayer_getCopyright()
{
    return (const char*)(fileHeader.copyright);
}

