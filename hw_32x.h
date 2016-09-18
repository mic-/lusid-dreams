#ifndef HW_32X_H
#define HW_32X_H

#include <stdarg.h>
#include <stdio.h>
#include <stdint.h>
#include <string.h>

extern void Hw32xSetFGColor(int32_t s, int32_t r, int32_t g, int32_t b);
extern void Hw32xSetBGColor(int32_t s, int32_t r, int32_t g, int32_t b);
extern void Hw32xInit(int32_t vmode);
extern int32_t Hw32xScreenGetX();
extern int32_t Hw32xScreenGetY();
extern void Hw32xScreenSetXY(int32_t x, int32_t y);
extern void Hw32xScreenClear();
extern void Hw32xScreenPutChar(int32_t x, int32_t y, uint8_t ch);
extern void Hw32xScreenClearLine(int32_t Y);
extern int32_t Hw32xScreenPrintData(const char *buff, int32_t size);
extern int32_t Hw32xScreenPuts(const char *str);
extern void Hw32xScreenPrintf(const char *format, ...);
extern void Hw32xDelay(int32_t ticks);
extern void Hw32xScreenFlip(int32_t wait);
extern void Hw32xFlipWait();

#endif
