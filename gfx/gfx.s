.global _PALETTE_DATA
.global _BACKGROUND_GFX
.global _SMALL_FONT
.global _BIG_FONT
.global _ARROWS
.global _SMALL_DIGITS

.section .text

.align 2

_PALETTE_DATA:  .incbin "gfx/dreams.pal"
	.incbin "gfx/c64font.pal"
	.incbin "gfx/bigfont1.pal"
	.incbin "gfx/bigfont1.pal"
	.incbin "gfx/arrows.pal"
	.incbin "gfx/small_digits.pal"

_BACKGROUND_GFX: .incbin "gfx/dreams.bin"
_SMALL_FONT: .incbin "gfx/c64font.bin"
_BIG_FONT: .incbin "gfx/bigfont1.bin"
_ARROWS: .incbin "gfx/arrows.bin"
_SMALL_DIGITS: .incbin "gfx/small_digits.bin"

.align 2


