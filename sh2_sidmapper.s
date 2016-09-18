.global _sidMapper_reset
.global _sidMapper_writeByte
.global	_RAM

.text

_sidMapper_reset:
	sts.l	pr,@-r15
	mov.l	.ramPlus1,r4
	mov		#0x36,r1
	mov.l	__CacheClearLine,r2
	mov.b	r1,@r4		! RAM[1] = 0x36
	jsr		@r2
	add		#-1,r4
	lds.l	@r15+,pr
	nop
	rts
	nop
	
	
! In: r0 = address
!     r1 = value
! Needs to preserve r0, r2, r9
_sidMapper_writeByte:
	extu.w	r0,r0
	mov		#5,r13
	mov		r0,r3
	shlr8	r3
	shlr2	r3
	shlr2	r3
	add		#-10,r3			! r3 = (address >> 12) - 0x0A
	cmp/hi	r13,r3			! unsigned comparison, will be true if (address >> 12) < 0x0A
	bt/s	.default_write
	extu.w	r0,r13			! save the address in r13 so that we can use r0 for other purposes
	mova	.page_lut,r0
	mov.b	@(r0,r3),r3
	braf	r3
	nop
.page_lut_base:

	.align 2
.page_lut:
	.byte	.write_page_a_b-.page_lut_base
	.byte	.write_page_a_b-.page_lut_base
	.byte	.default_write_and_restore_r0-.page_lut_base
	.byte	.write_page_d-.page_lut_base
	.byte	.write_page_e_f-.page_lut_base
	.byte	.write_page_e_f-.page_lut_base

	.align 2
.write_page_a_b:
	mov.b	@(1,r14),r0
	and		#3,r0
	cmp/eq	#3,r0			! is ((ram[1] & 3) == 3) ? (BASIC ROM mapped to $A000-BFFF)
	bt/s	.write_byte_ret
.default_write_and_restore_r0:	
	mov		r13,r0			! restore r0 (address)
.default_write:
	mov.b	r1,@(r0,r14)	! RAM[address] = value
.write_byte_ret:
	rts	
	nop

.write_page_d:
	mov.b	@(1,r14),r0
	and		#7,r0
	mov		#4,r3
	cmp/hi	r3,r0
	bt/s	.io_at_page_d
	! if (bankSelect == 4 || bankSelect == 0) write to RAM
	cmp/eq	#4,r0
	bt		.default_write_and_restore_r0
	tst		r0,r0
	bt/s	.default_write
	mov		r13,r0
	rts
	nop
.io_at_page_d:
	mov.w	.L22,r3
	mov.w	.mos6581_regs_last,r0
	add		r13,r3
	extu.w	r3,r3
	cmp/hi	r0,r3			! address > MOS6581_REGISTER_BASE+0x3FF ?
	bt/s	.write_byte_ret
	mov		r13,r0			! restore r0 (address)
	mov.l	r0,@-r15
	mov.l	r2,@-r15
	mov.l	r4,@-r15
	mov.l	r5,@-r15
	mov.l	r6,@-r15
	mov.l	r7,@-r15
	mov.l	r8,@-r15
	mov.l	r9,@-r15
	sts.l	pr,@-r15
	mov		r0,r4
	mov		r1,r5
	mov		r1,r8
	mov.w	.mos6581_regs_mask,r9
	mov.l	.mos6581_write_addr,r1
	and		r4,r9
	jsr		@r1				! mos6581_write(address & 0xD41F)
	mov		r9,r4
	mov.l	.mos6581_r_filter_modevol,r0
	cmp/eq	r0,r9
	bf		.write_byte_ret_2
	mov		#15,r4
	mov.l	.set_master_volume_addr,r1
	jsr		@r1
	and		r8,r4
.write_byte_ret_2:
	lds.l   @r15+,pr
	mov.l   @r15+,r9
	mov.l   @r15+,r8
	mov.l   @r15+,r7
	mov.l   @r15+,r6
	mov.l   @r15+,r5
	mov.l   @r15+,r4
	mov.l   @r15+,r2
	mov.l   @r15+,r0
	rts
	nop

.L22:
	.short	0x2C00
.mos6581_regs_last:
	.short	0x3FF
.mos6581_regs_mask:
	.short	0xD41F
.align 2
.mos6581_write_addr:
	.long	_mos6581_write
.mos6581_r_filter_modevol:
	.long	0xD418
.set_master_volume_addr:
	.long	_sidPlayer_setMasterVolume

.write_page_e_f:
	mov.b	@(1,r14),r0
	and		#3,r0
	mov		#1,r3
	cmp/gt	r3,r0
	bf/s	.default_write
	mov		r13,r0
	rts
	nop

.align 2
.ramPlus1: .long	_RAM+1
__CacheClearLine: .long _CacheClearLine

.section .bss
.comm	_RAM,65536



