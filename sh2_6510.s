! sh2_6510.s
! A 6510 emulator for the SuperH-2
! /Mic 2016

.global _emu6502_run
.global _emu6502_reset
.global _emu6502_setBrkVector
.global _regS
.global _regPC
.global _regF
.global _regY
.global _regX
.global _regA
.global _cpuCycles
.global _die

.text

! Register usage:
! 
!  R4:  return address for instructions
!  R5:  A
!  R6:  X
!  R7:  Y
!  R8:  F
!  R9:  scratch register not destroyed by external functions
!  R10: PC
!  R11: S
!  R12: cycles
!  R13: 
!  R14: pointer to RAM

.equ REG_A, r5
.equ REG_X, r6
.equ REG_Y, r7
.equ REG_F, r8
.equ REG_PC, r10

.equ FLAG_C, 0x01
.equ FLAG_Z, 0x02
.equ FLAG_I, 0x04
.equ FLAG_D, 0x08
.equ FLAG_B, 0x10
.equ FLAG_V, 0x40
.equ FLAG_N, 0x80

! ###########################################################################################################

.macro ADD_CYCLES cycnum
	add 	#\cycnum,r12
.endm

! Move the 6510 program counter <dist> bytes
.macro MOVE_PC dist 
	add 	#\dist,REG_PC
.endm

! The reason for using JMP instructions to jump to / return from
! the instruction handlers instead of JSR/RTS is to avoid the need
! of saving and restoring PR, since many of the instruction handlers
! will JSR to some memory access routine.
.macro RETURN
	jmp	@r4
.endm

.macro READ_BYTE dest,address
	mov		\address,r0
	mov.b	@(r0,r14),\dest
.endm

! ###########################################################################################################
! Calculate addresses
! ###########################################################################################################

! zp
! temp must not be r0
.macro ZP_ADDR dest,temp
	READ_BYTE \temp,r10
	add		#1,r10
	extu.b	\temp,\dest
.endm

! zp,X
! temp must not be r0
.macro ZPX_ADDR dest,temp
	READ_BYTE \temp,r10
	add		#1,r10
	add		r6,\temp
	extu.b	\temp,\dest
.endm

! zp,Y
! temp must not be r0
.macro ZPY_ADDR dest,temp
	READ_BYTE \temp,r10
	add		#1,r10
	add		r7,\temp
	extu.b	\temp,\dest
.endm

! abs
! dest must not be r0 or r9
.macro ABS_ADDR dest
	READ_BYTE r9,r10		! r9 = RAM[regPC]
	add		#1,r10			! regPC++
	READ_BYTE \dest,r10		! dest = RAM[regPC]
	add		#1,r10			! regPC++
	extu.b	\dest,\dest
	extu.b	r9,r9
	shll8	\dest
	or		r9,\dest		! dest = RAM[regPC] | (RAM[regPC + 1] << 8)
.endm

! abs,X
.macro ABSX_ADDR dest
	ABS_ADDR \dest
	add		r6,\dest
	extu.w	\dest,\dest
	! ToDo: add an extra cycle when adding X crosses a page boundary
.endm

! abs,Y
.macro ABSY_ADDR dest
	ABS_ADDR \dest
	add		r7,\dest
	extu.w	\dest,\dest
	! ToDo: add an extra cycle when adding Y crosses a page boundary
.endm
						
! (zp,X)
! Result in r1
.macro INDX_ADDR
	ZPX_ADDR r0,r1
	mov.b	@(r0,r14),r2
	add		#1,r0		
	extu.b	r0,r0
	extu.b	r2,r2
	mov.b	@(r0,r14),r1
	extu.b	r1,r1
	shll8	r1
	or		r2,r1
.endm

! (zp),Y
! Result in r1
.macro INDY_ADDR
	ZP_ADDR r9,r1
	READ_BYTE r2,r9		! r2 = RAM[RAM[regPC]]
	add		#1,r9		
	extu.b	r9,r9
	extu.b	r2,r2
	READ_BYTE r1,r9
	extu.b	r1,r1
	shll8	r1
	or		r2,r1
	add		r7,r1
	extu.w	r1,r1
	! ToDo: add extra cycle if adding Y makes the address cross a page boundary
.endm
						
! ###########################################################################################################
! Fetch operands
! ###########################################################################################################

.macro IMM_OP dest, temp
	ZP_ADDR \dest,\temp
.endm

.macro ZP_OP dest, temp
	ZP_ADDR r0,\temp
	mov.b	@(r0,r14),\dest
	extu.b	\dest,\dest
.endm

.macro ZPX_OP dest, temp
	ZPX_ADDR r0,\temp
	mov.b	@(r0,r14),\dest
	extu.b	\dest,\dest
.endm

.macro ZPY_OP dest, temp
	ZPY_ADDR \dest,\temp
	READ_BYTE \dest,\dest
	extu.b	\dest,\dest
.endm

.macro ABS_OP dest
	ABS_ADDR \dest
	READ_BYTE \dest,\dest
	extu.b	\dest,\dest
.endm

.macro ABSX_OP dest
	ABSX_ADDR \dest
	READ_BYTE \dest,\dest
	extu.b	\dest,\dest
.endm

.macro ABSY_OP dest
	ABSY_ADDR \dest
	READ_BYTE \dest,\dest
	extu.b	\dest,\dest
.endm

.macro INDX_OP dest
	INDX_ADDR
	READ_BYTE \dest,r1
	extu.b 	\dest,\dest
.endm

.macro INDY_OP dest
	INDY_ADDR
	READ_BYTE \dest,r1
	extu.b 	\dest,\dest
.endm

! ###########################################################################################################

.macro ADC_A operand
	extu.b	r8,r0
	mov		#0x3C,r9		! ~(FLAG_N|FLAG_V|FLAG_Z|FLAG_C)
	shlr	r0				! Carry -> T
	extu.b	r5,r0			! r0 = A
	and		r9,r8			! F &= ~(C|Z|V|N)
	addc 	\operand,r0		! r0 = A + operand + Carry (== result)
	mov 	r0,r2			! r2 = result
	extu.b	r0,r0
	cmp/eq	#0,r0
	movt 	r3
	mov		r5,r9			! r9 = oldA
	add		r3,r3			! Zero
	mov 	r0,r5			! A = result
	xor 	r0,\operand		! operand ^= result
	xor 	r0,r9			! r9 = oldA ^ result
	or		r3,r8
	and 	\operand,r9		! r9 = (oldA ^ result) & (operand ^ result)
	mov		#FLAG_V,r1
	shlr	r9
	and		r1,r9			! r9 = ((oldA ^ result) & (operand ^ result)) & 0x80 ? FLAG_V : 0
	mov 	r2,r0
	add		r1,r1			! r1 = FLAG_N
	or		r9,r8
	shlr8 	r0				! Carry
	and		r1,r2
	or 		r0,r8
	RETURN
	or		r2,r8
.endm

! ToDo: this could be optimized by performing the NOT operation in the xxx_OP macro
.macro SBC_A operand
	not		\operand,\operand
	extu.b	\operand,\operand
	ADC_A	\operand
.endm

! ###########################################################################################################

! AND/ORA/EOR
.macro BITWISE_LOGIC operation,operand,cycles
	mov		#0x7D,r9	! ~(FLAG_N|FLAG_Z)
	\operation	\operand,r5
	and		r9,r8		! F &= ~(FLAG_N|FLAG_Z)
	extu.b	r5,r0
	ADD_CYCLES \cycles
	tst		r0,r0
	and		#FLAG_N,r0
	movt	r1
	or		r0,r8
	add		r1,r1		! FLAG_Z
	RETURN
	or		r1,r8
.endm

! BIT
.macro BITop val,cycles
	mov		#0x3D,r9	! ~(FLAG_N|FLAG_V|FLAG_Z)
	tst		r5,\val
	and		r9,r8		! F &= ~(N|V|Z)
	movt	r2
	extu.b	\val,r0
	add		r2,r2		! FLAG_Z
	and		#0xC0,r0
	or		r2,r8
	ADD_CYCLES \cycles
	RETURN
	or		r0,r8
.endm
				 
! ###########################################################################################################

.macro ASL val
	mov		#0x7C,r0	! ~(FLAG_N|FLAG_Z|FLAG_C)
	exts.b	\val,\val	! bits[31:8] = bits[7]
	and		r0,r8		! F &= ~(N|Z|C)
	shll	\val		! val <<= 1, msb -> T
	movt	r2			! FLAG_C
	extu.b	\val,\val
	or		r2,r8
	mov		\val,r0
	tst		\val,\val
	and		#FLAG_N,r0
	movt	r2
	or		r0,r8
	add		r2,r2		! FLAG_Z
	or		r2,r8
.endm

.macro LSR val
	mov		#0x7C,r0	! ~(FLAG_N|FLAG_Z|FLAG_C)
	shlr	\val		! val >>= 1
	and		r0,r8
	movt	r2			! FLAG_C
	extu.b	\val,\val
	or		r2,r8		
	mov		\val,r0
	tst		\val,\val
	and		#FLAG_N,r0
	movt	r2
	or		r0,r8
	add		r2,r2		! FLAG_Z
	or		r2,r8
.endm

.macro ROL val
	mov		r8,r2
	mov		#0x7C,r0	! ~(FLAG_N|FLAG_Z|FLAG_C)
	shlr	r2			! C -> T
	exts.b	\val,\val	! bits[31:8] = bits[7]
	and		r0,r8
	rotcl	\val		! val = (val << 1) | C
	movt	r2			! FLAG_C
	extu.b	\val,\val
	or		r2,r8
	mov		\val,r0
	tst		\val,\val
	and		#FLAG_N,r0
	movt	r2
	or		r0,r8
	add		r2,r2		! FLAG_Z
	or		r2,r8
.endm

.macro ROR val
	extu.b	r8,r2
	mov		#0x7C,r0	! ~(FLAG_N|FLAG_Z|FLAG_C)
	shll8	r2	
	and		r0,r8		! F &= ~(N|Z|C)
	or		r2,\val
	shlr	\val		! val = (val >> 1) | (C << 7)
	movt	r2			! FLAG_C
	extu.b	\val,\val
	or		r2,r8
	mov		\val,r0
	tst		\val,\val
	and		#FLAG_N,r0
	movt	r2
	or		r0,r8
	add		r2,r2		! FLAG_Z
	or		r2,r8
.endm

! ###########################################################################################################
	             
.macro LDreg reg,cycles
	mov		#0x7D,r9	! ~(FLAG_N|FLAG_Z)
	extu.b	\reg,r0
	and		r9,r8		! F &= ~(FLAG_N|FLAG_Z)
	ADD_CYCLES \cycles
	tst		r0,r0
	and		#FLAG_N,r0
	movt	r1
	or		r0,r8
	add		r1,r1		! FLAG_Z
	RETURN
	or		r1,r8
.endm

.macro UPDATE_NZ val
	mov		#0x7D,r9	! ~(FLAG_N|FLAG_Z)
	extu.b	\val,r0
	and		r9,r8		! F &= ~(FLAG_N|FLAG_Z)
	tst		r0,r0
	and		#FLAG_N,r0
	movt	r2
	or		r0,r8
	add		r2,r2		! FLAG_Z
	or		r2,r8
.endm

! operand in r1
.macro CMPreg reg
	mov		#0x7C,r9	! ~(FLAG_N|FLAG_Z|FLAG_C)
	cmp/hs	r1,\reg
	extu.b	\reg,r2
	movt	r0			! r0 = (reg >= operand) ? FLAG_C : 0
	sub		r1,r2		! r2 = reg - operand
	and		r9,r8		! F &= ~(FLAG_N|FLAG_Z|FLAG_C)
	extu.b	r2,r2
	tst		r2,r2
	or		r0,r8		! FLAG_C
	movt	r1
	mov		r2,r0
	add		r1,r1		! FLAG_Z
	and		#FLAG_N,r0
	or		r1,r8
	or		r0,r8
.endm
				       
! ###########################################################################################################

! Perform the conditional branch if T=1
.macro COND_BRANCH_T
    bf/s \@f
    ADD_CYCLES 2
	READ_BYTE r1,r10
	add		#1,r10
	add		r10,r1		! addr = regPC + rel
	mov		r10,r9
	xor		r1,r9		! r9 = regPC ^ addr
	shlr8	r9
	shlr	r9			! T = ((regPC ^ addr) & 0x100) != 0
	mov		r1,r10
	RETURN
	addc	r9,r12		! cycles += (crossing page) ? 2 : 1
	\@:					! T == 0 -> just increment regPC
	RETURN
	add		#1,r10
.endm

! Perform the conditional branch if T=0
.macro COND_BRANCH_F cond
    bt/s \@f
    ADD_CYCLES 2
	READ_BYTE r1,r10
	add		#1,r10
	add		r10,r1		! addr = regPC + rel
	mov		r10,r9
	xor		r1,r9		! r9 = regPC ^ addr
	shlr8	r9
	shlr	r9			! T = ((regPC ^ addr) & 0x100) != 0
	mov		r1,r10
	RETURN
	addc	r9,r12		! cycles += (crossing page) ? 2 : 1
	\@:					! T == 1 -> just increment regPC
	RETURN
	add		#1,r10
.endm
                                  
! ###########################################################################################################

! value in r1
.macro PUSHB wb_func_label
	mov		#1,r0
	mov.l	\wb_func_label,r9
	shll8	r0
	jsr		@r9
	add		r11,r0	! r0 = S + 0x100
	add		#-1,r11
.endm

! value in r1
.macro PUSHW wb_func_label
	extu.b	r1,r2
	mov		#1,r0
	shlr8	r1
	mov.l	\wb_func_label,r9
	shll8	r0
	jsr		@r9
	add		r11,r0	! r0 = S + 0x100
	add		#-1,r0
	jsr		@r9
	extu.b	r2,r1
	add		#-2,r11
.endm
	               
.macro PULLB dest
	mov		#1,r9
	add		#1,r11
	shll8	r9
	add		r11,r9		! r9 = S + 0x100
	READ_BYTE \dest,r9
	extu.b	\dest,\dest
.endm

! ###########################################################################################################
	                
! == ADC ==

op_69:		! ADC imm
	IMM_OP r1,r1
	ADD_CYCLES 2
	ADC_A r1

op_65:		! ADC zp
	ZP_OP r1,r1
	ADD_CYCLES 3
	ADC_A r1

op_75:		! ADC zp,X
	ZPX_OP r1,r1
	ADD_CYCLES 4
	ADC_A r1

op_6D:		! ADC abs
	ABS_OP r1
	ADD_CYCLES 4
	ADC_A r1

op_7D:		! ADC abs,X
	ABSX_OP r1
	ADD_CYCLES 4
	ADC_A r1

op_79:		! ADC abs,Y
	ABSY_OP r1
	ADD_CYCLES 4
	ADC_A r1
			
op_61:		! ADC (zp,X)
	INDX_OP r1
	ADD_CYCLES 6
	ADC_A r1

op_71:		! ADC (zp),Y
	INDY_OP r1
	ADD_CYCLES 5
	ADC_A r1
			

! == AND ==
op_29:		! AND imm
	IMM_OP r1,r1
	BITWISE_LOGIC and,r1,2

op_25:		! AND zp
	ZP_OP r1,r1
	BITWISE_LOGIC and,r1,3

op_35:		! AND zp,X
	ZPX_OP r1,r1
	BITWISE_LOGIC and,r1,4

op_2D:		! AND abs
	ABS_OP r1
	BITWISE_LOGIC and,r1,4

op_3D:		! AND abs,X
	ABSX_OP r1
	BITWISE_LOGIC and,r1,4

op_39:		! AND abs,Y
	ABSY_OP r1
	BITWISE_LOGIC and,r1,4

op_21:		! AND (zp,X)
	INDX_OP r1
	BITWISE_LOGIC and,r1,6

op_31:		! AND (zp),Y
	INDY_OP	r1
	BITWISE_LOGIC and,r1,5
			

! == ASL ==
op_0A:		! ASL A
	ASL r5
	RETURN
	ADD_CYCLES 2

op_06:		! ASL zp
	ZP_ADDR r9,r9
	READ_BYTE r1,r9
	ASL 	r1
	mov 	r9,r0
	mov.b 	r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5

op_16:		! ASL zp,X
	ZPX_ADDR r9,r9
	READ_BYTE r1,r9
	ASL 	r1
	mov 	r9,r0
	mov.b 	r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5

op_0E:		! ASL abs
	ABS_ADDR r1
	READ_BYTE r9,r1
	ASL 	r9
	mov.l 	asl_write_byte,r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 6

op_1E:		! ASL abs,X
	ABSX_ADDR r1
	READ_BYTE r9,r1
	ASL 	r9
	mov.l 	asl_write_byte,r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 6

.align 2			
asl_write_byte: .long _sidMapper_writeByte


! == Bxx ==
op_10:		! BPL rel
	exts.b	r8,r0
	cmp/pz	r0
	COND_BRANCH_T
	
op_30:		! BMI rel
	exts.b	r8,r0
	cmp/pz	r0
	COND_BRANCH_F

op_50:		! BVC rel
	extu.b	r8,r0
	tst		#FLAG_V,r0
	COND_BRANCH_T

op_70:		! BVS rel
	extu.b	r8,r0
	tst		#FLAG_V,r0
	COND_BRANCH_F

op_90:		! BCC rel
	extu.b	r8,r0
	tst		#FLAG_C,r0
	COND_BRANCH_T

op_B0:		! BCS rel
	extu.b	r8,r0
	tst		#FLAG_C,r0
	COND_BRANCH_F

op_D0:		! BNE rel
	extu.b	r8,r0
	tst		#FLAG_Z,r0
	COND_BRANCH_T

op_F0:		! BEQ rel
	extu.b	r8,r0
	tst		#FLAG_Z,r0
	COND_BRANCH_F
			

! == BIT ==
op_24:		! BIT zp
	ZP_OP r1,r1
	BITop r1,3

op_2C:		! BIT abs
	ABS_OP r1
	BITop r1,4
			

! ====
op_00:		! BRK
	add		#1,r10
	extu.w	r10,r1
	PUSHW brk_write_byte
	mov		r8,r0
	or		#0x30,r0
	extu.b	r0,r1
	PUSHB brk_write_byte
	mov		#(FLAG_B|FLAG_I),r0
	or		r0,r8
	mov.l	brk_brkVector,r1
	mov.l	@r1,r10
	ABS_ADDR r1
	extu.w	r1,r10
	RETURN
	ADD_CYCLES 7

.align 2
brk_write_byte: .long _sidMapper_writeByte
brk_brkVector: .long brkVector

			
! == CLx ==

op_18:		! CLC
	mov #FLAG_C,r1
	not r1,r1
	ADD_CYCLES 2
	RETURN	
	and r1,r8

op_D8:		! CLD
	mov #FLAG_D,r1
	not r1,r1
	ADD_CYCLES 2
	RETURN	
	and r1,r8

op_58:		! CLI
	mov #FLAG_I,r1
	not r1,r1
	ADD_CYCLES 2
	RETURN	
	and r1,r8

op_B8:		! CLV
	mov #FLAG_V,r1
	not r1,r1
	ADD_CYCLES 2
	RETURN	
	and r1,r8


! == CMP ==
op_C9:		! CMP imm
	IMM_OP r1,r1
	CMPreg r5
	RETURN
	ADD_CYCLES 2

op_C5:		! CMP zp
	ZP_OP r1,r1
	CMPreg r5
	RETURN
	ADD_CYCLES 3

op_D5:		! CMP zp,X
	ZPX_OP r1,r1
	CMPreg r5
	RETURN
	ADD_CYCLES 4

op_CD:		! CMP abs
	ABS_OP r1
	CMPreg r5
	RETURN
	ADD_CYCLES 4

op_DD:		! CMP abs,X
	ABSX_OP r1
	CMPreg r5
	RETURN
	ADD_CYCLES 4

op_D9:		! CMP abs,Y
	ABSY_OP r1
	CMPreg r5
	RETURN
	ADD_CYCLES 4

op_C1:		! CMP (zp,X)
	INDX_OP r1
	CMPreg r5
	RETURN
	ADD_CYCLES 6

op_D1:		! CMP (zp),Y
	INDY_OP r1
	CMPreg r5
	RETURN
	ADD_CYCLES 5
			

! == CPX ==
op_E0:		! CPX imm
	IMM_OP r1,r1
	CMPreg r6
	RETURN
	ADD_CYCLES 2

op_E4:		! CPX zp
	ZP_OP r1,r1
	CMPreg r6
	RETURN
	ADD_CYCLES 3

op_EC:		! CPX abs
	ABS_OP r1
	CMPreg r6
	RETURN
	ADD_CYCLES 4

! == CPY ==
op_C0:		! CPY imm
	IMM_OP r1,r1
	CMPreg r7
	RETURN
	ADD_CYCLES 2

op_C4:		! CPY zp
	ZP_OP r1,r1
	CMPreg r7
	RETURN
	ADD_CYCLES 3

op_CC:		! CPY abs
	ABS_OP r1
	CMPreg r7
	RETURN
	ADD_CYCLES 4
			
			
! == DEC ==
op_C6:		! DEC zp
	ZP_ADDR r3,r1
	READ_BYTE r1,r3
	add #-1,r1
	UPDATE_NZ r1
	mov r3,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5
	
op_D6:		! DEC zp,X
	ZPX_ADDR r3,r1
	READ_BYTE r1,r3
	add #-1,r1
	UPDATE_NZ r1
	mov r3,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 6

op_CE:		! DEC abs
	ABS_ADDR r3
	READ_BYTE r1,r3
	add #-1,r1
	UPDATE_NZ r1
	mov.l dec_write_byte,r9
	jsr @r9
	mov r3,r0
	RETURN
	ADD_CYCLES 6

op_DE:		! DEC abs,X
	ABSX_ADDR r3
	READ_BYTE r1,r3
	add #-1,r1
	UPDATE_NZ r1
	mov.l dec_write_byte,r9
	jsr @r9
	mov r3,r0
	RETURN
	ADD_CYCLES 6

.align 2
dec_write_byte: .long _sidMapper_writeByte


! ====
op_CA:		! DEX
	add		#-1,r6
	extu.b	r6,r6
	LDreg 	r6,2

op_88:		! DEY
	add		#-1,r7
	extu.b	r7,r7
	LDreg 	r7,2

			
! == EOR ==
op_49:		! EOR imm
	IMM_OP r1,r1
	BITWISE_LOGIC xor,r1,2

op_45:		! EOR zp
	ZP_OP r1,r1
	BITWISE_LOGIC xor,r1,3

op_55:		! EOR zp,X
	ZPX_OP r1,r1
	BITWISE_LOGIC xor,r1,4

op_4D:		! EOR abs
	ABS_OP r1
	BITWISE_LOGIC xor,r1,4

op_5D:		! EOR abs,X
	ABSX_OP r1
	BITWISE_LOGIC xor,r1,4

op_59:		! EOR abs,Y
	ABSY_OP r1
	BITWISE_LOGIC xor,r1,4

op_41:		! EOR (zp,X)
	INDX_OP r1
	BITWISE_LOGIC xor,r1,6

op_51:		! EOR (zp),Y
	INDY_OP r1
	BITWISE_LOGIC xor,r1,5
			

! == INC ==
op_E6:		! INC zp
	ZP_ADDR r3,r1
	READ_BYTE r1,r3
	add #1,r1
	UPDATE_NZ r1
	mov r3,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5
	
op_F6:		! INC zp,X
	ZPX_ADDR r3,r1
	READ_BYTE r1,r3
	add #1,r1
	UPDATE_NZ r1
	mov r3,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 6
	
op_EE:		! INC abs
	ABS_ADDR r3
	READ_BYTE r1,r3
	add #1,r1
	UPDATE_NZ r1
	mov.l inc_write_byte,r9
	jsr @r9
	mov r3,r0
	RETURN
	ADD_CYCLES 6
	
op_FE:		! INC abs,X
	ABSX_ADDR r3
	READ_BYTE r1,r3
	add #1,r1
	UPDATE_NZ r1
	mov.l inc_write_byte,r9
	jsr @r9
	mov r3,r0
	RETURN
	ADD_CYCLES 6
	
.align 2
inc_write_byte: .long _sidMapper_writeByte

			
! ====
op_E8:		! INX
	add		#1,r6
	extu.b	r6,r6
	LDreg	r6,2

op_C8:		! INY
	add		#1,r7
	extu.b	r7,r7
	LDreg	r7,2
			

! ====
op_4C:		! JMP abs
	mov		r10,r2
	ABS_ADDR r1
	add		#-1,r2
	mov		r1,r10
	cmp/eq	r1,r2
	bf/s	_jmp_not_inf_loop
	ADD_CYCLES 3
	mov.l	__ce_done,r9
	jmp		@r9
	nop
_jmp_not_inf_loop:
	RETURN
	nop

.align 2
__ce_done: .long _ce_done

op_6C:		! JMP (abs)
	ABS_ADDR r1
	READ_BYTE r2,r1
	extu.b	r1,r0
	shlr8	r1
	add		#1,r0
	shll8	r1
	extu.b	r0,r0
	extu.b	r2,r10
	or		r0,r1
	READ_BYTE r2,r1
	shll8	r2
	or		r2,r10
	ADD_CYCLES 5
	RETURN
	extu.w	r10,r10
			
op_20:		! JSR abs
	mov		r10,r1
	ABS_ADDR r2
	add		#1,r1
	extu.w	r2,r10
	PUSHW jsr_write_byte
	RETURN
	ADD_CYCLES 6

.align 2
jsr_write_byte: .long _sidMapper_writeByte

			
! == LAX ==
op_A7:		! LAX zp
	ZP_OP 	r5,r1
	mov		r5,r6
	LDreg 	r5,3

op_B7:		! LAX zp,Y
	ZPY_OP 	r5,r1
	mov		r5,r6
	LDreg 	r5,4

op_AF:		! LAX abs
	ABS_OP 	r5
	mov		r5,r6
	LDreg 	r5,4

op_BF:		! LAX abs,Y
	ABSY_OP	r5
	mov		r5,r6
	LDreg	r5,4

op_B3:		! LAX (zp),Y
	INDY_OP	r5
	mov		r5,r6
	LDreg	r5,5

			
! == LDA ==
op_A9:		! LDA imm
	IMM_OP r5,r5
	LDreg r5,2

op_A5:		! LDA zp
	ZP_OP r5,r5
	LDreg r5,3

op_B5:		! LDA zp,X
	ZPX_OP r5,r5
	LDreg r5,4

op_AD:		! LDA abs
	ABS_OP r5
	LDreg r5,4

op_BD:		! LDA abs,X
	ABSX_OP r5
	LDreg r5,4
			
op_B9:		! LDA abs,Y
	ABSY_OP r5
	LDreg r5,4

op_A1:		! LDA (zp,X)
	INDX_OP r5
	LDreg r5,6

op_B1:		! LDA (zp),Y
	INDY_OP r5
	LDreg r5,5


! == LDX ==
op_A2:		! LDX imm
	IMM_OP r6,r1
	LDreg r6,2

op_A6:		! LDX zp
	ZP_OP r6,r1
	LDreg r6,3

op_B6:		! LDX zp,Y
	ZPY_OP r6,r1
	LDreg r6,4

op_AE:		! LDX abs
	ABS_OP r6
	LDreg r6,4
	
op_BE:		! LDX abs,Y
	ABSY_OP r6
	LDreg r6,4
		

! == LDY ==
op_A0:		! LDY imm
	IMM_OP r7,r1
	LDreg r7,2

op_A4:		! LDY zp
	ZP_OP r7,r1
	LDreg r7,3

op_B4:		! LDY zp,X
	ZPX_OP r7,r1
	LDreg r7,4

op_AC:		! LDY abs
	ABS_OP r7
	LDreg r7,4

op_BC:		! LDY abs,X
	ABSX_OP r7
	LDreg r7,4


! == LSR ==
op_4A:		! LSR A
	LSR r5
	RETURN
	ADD_CYCLES 2

op_46:		! LSR zp
	ZP_ADDR r9,r9
	READ_BYTE r1,r9
	extu.b 	r1,r1
	LSR 	r1
	mov 	r9,r0
	mov.b 	r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5

op_56:		! LSR zp,X
	ZPX_ADDR r9,r9
	READ_BYTE r1,r9
	extu.b r1,r1
	LSR 	r1
	mov 	r9,r0
	mov.b 	r1,@(r0,r14)
	RETURN
	ADD_CYCLES 6

op_4E:		! LSR abs
	ABS_ADDR r1
	READ_BYTE r9,r1
	extu.b 	r9,r9
	LSR 	r9
	mov.l 	lsr_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 6

op_5E:		! LSR abs,X
	ABSX_ADDR r1
	READ_BYTE r9,r1
	extu.b 	r9,r9
	LSR 	r9
	mov.l 	lsr_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 7

.align 2
lsr_write_byte: .long _sidMapper_writeByte

! == NOP ==
op_EA:		! NOP
op_1A:
op_3A:
op_5A:
op_7A:
op_DA:
	RETURN
	ADD_CYCLES 2


! == ORA ==
op_09:		! ORA imm
	IMM_OP r1,r1
	BITWISE_LOGIC or,r1,2

op_05:		! ORA zp
	ZP_OP r1,r1
	BITWISE_LOGIC or,r1,3

op_15:		! ORA zp,X
	ZPX_OP r1,r1
	BITWISE_LOGIC or,r1,4

op_0D:		! ORA abs
	ABS_OP r1
	BITWISE_LOGIC or,r1,4

op_1D:		! ORA abs,X
	ABSX_OP r1
	BITWISE_LOGIC or,r1,4

op_19:		! ORA abs,Y
	ABSY_OP r1
	BITWISE_LOGIC or,r1,4

op_01:		! ORA (zp,X)
	INDX_OP r1
	BITWISE_LOGIC or,r1,6

op_11:		! ORA (zp),Y
	INDY_OP r1
	BITWISE_LOGIC or,r1,5
			

! == PHx ==
op_48:		! PHA
	extu.b	r5,r1
	PUSHB phx_write_byte
	RETURN
	ADD_CYCLES 3

op_08:		! PHP
	extu.b	r8,r1
	PUSHB phx_write_byte
	RETURN
	ADD_CYCLES 3

.align 2
phx_write_byte: .long _sidMapper_writeByte

			
! == PLx ==
op_68:		! PLA
	PULLB r5
	LDreg r5,4

op_28:		! PLP
	PULLB r8
	RETURN
	ADD_CYCLES 4
			

! == ROL ==
op_2A:		! ROL A
	ROL r5
	RETURN
	ADD_CYCLES 2

op_26:		! ROL zp
	ZP_ADDR r9,r9
	READ_BYTE r1,r9
	ROL r1
	mov r9,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5

op_36:		! ROL zp,X
	ZPX_ADDR r9,r9
	READ_BYTE r1,r9
	ROL r1
	mov r9,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 6

op_2E:		! ROL abs
	ABS_ADDR r1
	READ_BYTE r9,r1
	ROL 	r9
	mov.l 	ror_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 6

op_3E:		! ROL abs,X
	ABSX_ADDR r1
	READ_BYTE r9,r1
	ROL 	r9
	mov.l 	ror_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 7


! == ROR ==
op_6A:		! ROR A
	ROR r5
	RETURN
	ADD_CYCLES 2

op_66:		! ROR zp
	ZP_ADDR r9,r9
	READ_BYTE r1,r9
	extu.b 	r1,r1
	ROR r1
	mov r9,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 5

op_76:		! ROR zp,X
	ZPX_ADDR r9,r9
	READ_BYTE r1,r9
	extu.b 	r1,r1
	ROR r1
	mov r9,r0
	mov.b r1,@(r0,r14)
	RETURN
	ADD_CYCLES 6
	
op_6E:		! ROR abs
	ABS_ADDR r1
	READ_BYTE r9,r1
	extu.b 	r9,r9
	ROR 	r9
	mov.l 	ror_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 6
	
op_7E:		! ROR abs,X
	ABSX_ADDR r1
	READ_BYTE r9,r1
	extu.b 	r9,r9
	ROR 	r9
	mov.l 	ror_write_byte, r2
	mov 	r1,r0
	jsr 	@r2
	mov 	r9,r1
	RETURN
	ADD_CYCLES 7
	
.align 2
ror_write_byte: .long _sidMapper_writeByte

			
! ====
op_40:		! RTI
	PULLB 	r8
	PULLB 	r10
	PULLB 	r2
	shll8 	r2
	or		r2,r10
	RETURN
	ADD_CYCLES 6

op_60:		! RTS
	PULLB 	r10
	PULLB 	r2
	shll8 	r2
	or		r2,r10
	add		#1,r10
	RETURN
	ADD_CYCLES 6
			
			
! == SBC ==
op_E9:		! SBC imm
	IMM_OP r1,r1
	ADD_CYCLES 2
	SBC_A r1
	
op_E5:		! SBC zp
	ZP_OP r1,r1
	ADD_CYCLES 3
	SBC_A r1

op_F5:		! SBC zp,X
	ZPX_OP r1,r1
	ADD_CYCLES 4
	SBC_A r1

op_ED:		! SBC abs
	ABS_OP r1
	ADD_CYCLES 4
	SBC_A r1
			
op_FD:		! SBC abs,X
	ABSX_OP r1
	ADD_CYCLES 4
	SBC_A r1

op_F9:		! SBC abs,Y
	ABSY_OP r1
	ADD_CYCLES 4
	SBC_A r1

op_E1:		! SBC (zp,X)
	INDX_OP r1
	ADD_CYCLES 6
	SBC_A r1

op_F1:		! SBC (zp),Y
	INDY_OP r1
	ADD_CYCLES 5
	SBC_A r1
			
			
! == SEx ==
op_38:		! SEC
	mov		#FLAG_C,r1
	ADD_CYCLES 2
	RETURN
	or		r1,r8

op_F8:		! SED
	mov		#FLAG_D,r1
	ADD_CYCLES 2
	RETURN
	or		r1,r8

op_78:		! SEI
	mov		#FLAG_I,r1
	ADD_CYCLES 2
	RETURN
	or		r1,r8


! == STA ==
op_85:		! STA zp
	ZP_ADDR	r0,r1
	mov.b 	r5,@(r0,r14)
	RETURN
	ADD_CYCLES 3
	
op_95:		! STA zp,X
	ZPX_ADDR r0,r1
	mov.b 	r5,@(r0,r14)
	RETURN
	ADD_CYCLES 4

op_8D:		! STA abs
	ABS_ADDR r2
	mov.l	sta_write_byte,r9
	mov		r5,r1
	jsr		@r9
	mov		r2,r0
	RETURN
	ADD_CYCLES 4

op_9D:		! STA abs,X
	ABSX_ADDR r2
	mov.l	sta_write_byte,r9
	mov		r5,r1
	jsr		@r9
	mov		r2,r0
	RETURN
	ADD_CYCLES 4

op_99:		! STA abs,Y
	ABSY_ADDR r2
	mov.l	sta_write_byte,r9
	mov		r5,r1
	jsr		@r9
	mov		r2,r0
	RETURN
	ADD_CYCLES 4

op_81:		! STA (zp,X)
	INDX_ADDR
	mov.l	sta_write_byte,r9
	mov		r1,r0
	jsr		@r9
	mov		r5,r1
	RETURN
	ADD_CYCLES 6

op_91:		! STA (zp),Y
	INDY_ADDR
	mov.l	sta_write_byte,r9
	mov		r1,r0
	jsr		@r9
	mov		r5,r1
	RETURN
	ADD_CYCLES 5
			
.align 2
sta_write_byte: .long _sidMapper_writeByte


! == STX ==
op_86:		! STX zp
	ZP_ADDR	r0,r1
	mov.b 	r6,@(r0,r14)
	RETURN
	ADD_CYCLES 3

op_96:		! STX zp,Y
	ZPY_ADDR r0,r1
	mov.b 	r6,@(r0,r14)
	RETURN
	ADD_CYCLES 4

op_8E:		! STX abs
	ABS_ADDR r2
	mov.l	stx_write_byte,r9
	mov		r6,r1
	jsr		@r9
	mov		r2,r0
	RETURN
	ADD_CYCLES 4
			
.align 2
stx_write_byte: .long _sidMapper_writeByte

! == STY ==
op_84:		! STY zp
	ZP_ADDR	r0,r1
	mov.b r7,@(r0,r14)
	RETURN
	ADD_CYCLES 3

op_94:		! STY zp,X
	ZPX_ADDR r0,r1
	mov.b r7,@(r0,r14)
	RETURN
	ADD_CYCLES 4

op_8C:		! STY abs
	ABS_ADDR r2
	mov.l	sty_write_byte,r9
	mov		r7,r1
	jsr		@r9
	mov		r2,r0
	RETURN
	ADD_CYCLES 4
			
.align 2
sty_write_byte: .long _sidMapper_writeByte


! == Txx ==
op_AA:		! TAX
	mov		r5,r6
	LDreg 	r6,2

op_A8:		! TAY
	mov 	r5,r7
	LDreg 	r7,2

op_BA:		! TSX
	mov		r11,r6
	LDreg 	r6,2

op_8A:		! TXA
	mov		r6,r5
	LDreg	r5,2

op_9A:		! TXS
	mov		r6,r11
	RETURN
	ADD_CYCLES 2

op_98:		! TYA
	mov		r7,r5
	LDreg	r5,2

! === Illegal/undocumented opcodes

op_02: op_03: op_04: op_07: op_0B: op_0C: op_0F:
op_12: op_13: op_14: op_17: op_1B: op_1C: op_1F:
op_22: op_23: op_27: op_2B: op_2F:
op_32: op_33: op_34: op_37: op_3B: op_3C: op_3F:
op_42: op_43: op_44: op_47: op_4B: op_4F:
op_52: op_53: op_54: op_57: op_5B: op_5C: op_5F:
op_62: op_63: op_64: op_67: op_6B: op_6F:
op_72: op_73: op_74: op_77: op_7B: op_7C: op_7F:
op_80: op_82: op_83: op_87: op_89: op_8B: op_8F:
op_92: op_93: op_97: op_9B: op_9C: op_9E: op_9F:
op_A3: op_AB:
op_B2: op_BB: 
op_C2: op_C3: op_C7: op_CB: op_CF:
op_D2: op_D3: op_D4: op_D7: op_DB: op_DC: op_DF:
op_E2: op_E3: op_E7: op_EB: op_EF:
op_F2: op_F3: op_F4: op_F7: op_FA: op_FB: op_FC: op_FF:

	bra op_02
	nop
	
! ###########################################################################################################
			
! Jump table for instruction handlers
.align 2
opcode_table:
	.long op_00,op_01,op_02,op_03,op_04,op_05,op_06,op_07
	.long op_08,op_09,op_0A,op_0B,op_0C,op_0D,op_0E,op_0F
	.long op_10,op_11,op_12,op_13,op_14,op_15,op_16,op_17
	.long op_18,op_19,op_1A,op_1B,op_1C,op_1D,op_1E,op_1F
	.long op_20,op_21,op_22,op_23,op_24,op_25,op_26,op_27
	.long op_28,op_29,op_2A,op_2B,op_2C,op_2D,op_2E,op_2F
	.long op_30,op_31,op_32,op_33,op_34,op_35,op_36,op_37
	.long op_38,op_39,op_3A,op_3B,op_3C,op_3D,op_3E,op_3F
	.long op_40,op_41,op_42,op_43,op_44,op_45,op_46,op_47
	.long op_48,op_49,op_4A,op_4B,op_4C,op_4D,op_4E,op_4F
	.long op_50,op_51,op_52,op_53,op_54,op_55,op_56,op_57
	.long op_58,op_59,op_5A,op_5B,op_5C,op_5D,op_5E,op_5F
	.long op_60,op_61,op_62,op_63,op_64,op_65,op_66,op_67
	.long op_68,op_69,op_6A,op_6B,op_6C,op_6D,op_6E,op_6F
	.long op_70,op_71,op_72,op_73,op_74,op_75,op_76,op_77
	.long op_78,op_79,op_7A,op_7B,op_7C,op_7D,op_7E,op_7F
	.long op_80,op_81,op_82,op_83,op_84,op_85,op_86,op_87
	.long op_88,op_89,op_8A,op_8B,op_8C,op_8D,op_8E,op_8F
	.long op_90,op_91,op_92,op_93,op_94,op_95,op_96,op_97
	.long op_98,op_99,op_9A,op_9B,op_9C,op_9D,op_9E,op_9F
	.long op_A0,op_A1,op_A2,op_A3,op_A4,op_A5,op_A6,op_A7
	.long op_A8,op_A9,op_AA,op_AB,op_AC,op_AD,op_AE,op_AF
	.long op_B0,op_B1,op_B2,op_B3,op_B4,op_B5,op_B6,op_B7
	.long op_B8,op_B9,op_BA,op_BB,op_BC,op_BD,op_BE,op_BF
	.long op_C0,op_C1,op_C2,op_C3,op_C4,op_C5,op_C6,op_C7
	.long op_C8,op_C9,op_CA,op_CB,op_CC,op_CD,op_CE,op_CF
	.long op_D0,op_D1,op_D2,op_D3,op_D4,op_D5,op_D6,op_D7
	.long op_D8,op_D9,op_DA,op_DB,op_DC,op_DD,op_DE,op_DF
	.long op_E0,op_E1,op_E2,op_E3,op_E4,op_E5,op_E6,op_E7
	.long op_E8,op_E9,op_EA,op_EB,op_EC,op_ED,op_EE,op_EF
	.long op_F0,op_F1,op_F2,op_F3,op_F4,op_F5,op_F6,op_F7
	.long op_F8,op_F9,op_FA,op_FB,op_FC,op_FD,op_FE,op_FF


_emu6502_setBrkVector:
	mov.l 	_brkVector,r1
	mov.l	r4,@r1
	rts
	nop


_emu6502_reset:
	mov		#0xfe,r0
	mov.l	_brkVector,r1
	extu.w	r0,r0		! fffe
	mov		#0,r8		!  clear flags
	mov.l	r0,@r1
	rts
	nop

.align 2
_brkVector: .long brkVector


_emu6502_run:
	mov.l	r8,@-r15
	mov.l	r9,@-r15
	mov.l	r10,@-r15
	mov.l	r11,@-r15
	mov.l	r12,@-r15
	mov.l	r13,@-r15
	mov.l	r14,@-r15
	sts.l	pr,@-r15
	mov.l	r4,@-r15		! maxCycles
	
	mov.l	__cpu_instr_done,r4
	mov.l	__regS,r1
	mov.l	@r1+,r11
	mov.l	@r1+,r10
	mov.l	@r1+,r8
	mov.l	@r1+,r7
	mov.l	@r1+,r6
	mov.l	@r1+,r5
	mov.l	@r1+,r12

	mov.l	__RAM,r14
	
_cpu_execute_loop:
	READ_BYTE r1,r10	! r1 = RAM[regPC]
	add		#1,r10		! regPC++
	extu.b	r1,r1
	mov.l	__opcode_table,r0
	shll2	r1
	mov.l	@(r0,r1),r9
	jmp		@r9
	nop
	
_cpu_instr_done:	
	mov.l	@r15,r0		! maxCycles
	cmp/hs	r0,r12
	bt	_ce_done
	bra	_cpu_execute_loop
	nop
_ce_done:

	mov.l	__regS,r1
	add		#(7*4),r1
	mov.l	r12,@-r1
	mov.l	r5,@-r1
	mov.l	r6,@-r1
	mov.l	r7,@-r1
	mov.l	r8,@-r1
	mov.l	r10,@-r1
	mov.l	r11,@-r1
	
	mov.l	@r15+,r0	! maxCycles (discarded)
	lds.l	@r15+,pr
	mov.l	@r15+,r14
	mov.l	@r15+,r13
	mov.l	@r15+,r12
	mov.l	@r15+,r11
	mov.l	@r15+,r10
	mov.l	@r15+,r9
	mov.l	@r15+,r8
	nop
	rts
	nop

.align 2

	
__regS: .long _regS
__RAM: .long _RAM
__opcode_table:	.long opcode_table
__cpu_instr_done: .long _cpu_instr_done	

_die:
	bra _die
	nop
	
.data
.align 2
_regS: .long 0
_regPC: .long 0
_regF: .long 0
_regY: .long 0
_regX: .long 0
_regA: .long 0
_cpuCycles: .long 0
brkVector: .long 0
cpu_max_cycles: .long 0

