ROOTDIR = /c/gendev/GNUSHv13.01-ELF


LDSCRIPTSDIR = .

LIBPATH = -L$(ROOTDIR)/sh-elf/lib -L$(ROOTDIR)/sh-elf/lib/gcc/sh-elf/4.7-GNUSH_v13.01 -L$(ROOTDIR)/sh-elf/sh-elf/lib
INCPATH = -I. -I$(ROOTDIR)/sh-elf/include -I$(ROOTDIR)/sh-elf/sh-elf/include

CCFLAGS = -m2 -mb -O2 -std=c99 -Wall -c -fomit-frame-pointer
CCFLAGS += -D__32X__ -DUSE_VOL_ENVELOPE -DEMU6502_ASM
HWFLAGS = -m2 -mb -O1 -std=c99 -Wall -c -fomit-frame-pointer
LDFLAGS = -T $(LDSCRIPTSDIR)/mars.ld -Wl,-Map=output.map -nostdlib
ASFLAGS = --big --defsym LINEAR_CROSSFADE=1

PREFIX = $(ROOTDIR)/sh-elf/bin/sh-elf-
CC = $(PREFIX)gcc
AS = $(PREFIX)as
LD = $(PREFIX)ld
OBJC = $(PREFIX)objcopy

DD = dd
RM = rm -f

TARGET = sidplay
LIBS = $(LIBPATH) -lc -lgcc -lgcc-Os-4-200 -lnosys
OBJS = \
	crt0.o \
	main.o \
	sound.o \
	hw_32x.o \
	mixer.o \
	mos6581.o \
	sh2_sidmapper.o \
	sidplayer.o \
	songs/songs.o \
	gfx/gfx.o \
	font.o \
	sh2_6510.o


all: $(TARGET).bin

#m68k.bin:
#	make -C src-md

$(TARGET).bin: $(TARGET).elf
	$(OBJC) -O binary $< temp.bin
	$(DD) if=temp.bin of=$@ bs=256K conv=sync

$(TARGET).elf: $(OBJS)
	$(CC) $(LDFLAGS) $(OBJS) $(LIBS) -o $(TARGET).elf

hw_32x.o: hw_32x.c
	$(CC) $(HWFLAGS) $(INCPATH) $< -o $@

%.o: %.c
	$(CC) $(CCFLAGS) $(INCPATH) $< -o $@

%.o: %.s
	$(AS) $(ASFLAGS) $(INCPATH) $< -o $@

clean:
	$(RM) music/*.o *.o *.bin *.elf output.map
