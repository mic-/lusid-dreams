.text

! void MixSidVoices(int16_t *filtered, int16_t *src, uint32_t count);
! On entry: r4 = pointer to buffer that will receive the mixed/filtered samples (mono)
!           r5 = input buffer pointer (3x mono, deinterleaved, 12-bit unsigned)
!           r6 = count (number of samples)
!
	.align 4
	.global _MixSidVoices
_MixSidVoices:
        mov.l   r7,@-r15
        mov.l   r9,@-r15
        mov.l   r10,@-r15
        mov.l   r11,@-r15
        mov.l   r12,@-r15

	mov.l sampleBias,r0
	mov.l @r0,r12

	mov	r6,r11
	add	r11,r11
	mov	r5,r10
	add	r11,r10		/* r10 = &input[count]  (Voice B) */
	add	r11,r11
	add	r5,r11		/* r11 = &input[count*2]  (Voice C) */
	
	mov.l	masterVolume,r2
	mov		#224,r1
	mov.l	mixFactor,r0
	mov.l	@r2,r7
	extu.b	r1,r1
	mov.l	@r0,r2
	muls.w	r7,r2		
	sts	macl,r7		/* r7 = mixFactor * masterVolume */
	
	mov.w 	@r5+,r0		/* r0 = srcA[0] */
	mov.w	@r10+,r2	/* r2 = srcB[0] */
	add	r2,r0
	mov.w	@r11+,r2	/* r2 = srcC[0] */
	add	r2,r0		/* r0 = srcA[0] + srcB[0] + srcC[0] */
	muls.w	r0,r7		/* macl = mixFactor * masterVolume * (srcA[0] + srcB[0] + srcC[0]) */
	sts	macl,r0
	shlr16	r0

	mov	r0,r3
	add	r12,r0
	mov.w 	r0,@r4		/* filteredA[0] = srcA[0]
	dt	r6
	/* for i = 1..count-1 do */
        /*   mixed = (mixFactor * masterVolume * (srcA[i] + srcB[i] + srcC[i])) >> 16 */
        /*   filtered[i] = filtered[i-1] + 203/256 * (mixed - filtered[i-1]) */
filter_loop:
	mov.w 	@r5+,r0		/* r0 = srcA[i] */
	mov.w 	@r10+,r2	/* r2 = srcB[i] */
	mov.w 	@r11+,r9	/* r9 = srcC[i] */
	add	r2,r0
	add	r9,r0		/* r0 = srcA[i] + srcB[i] + srcC[i] */
	muls.w	r0,r7	
	sts	macl,r0
	shlr16	r0		/* r0 = (mixFactor * masterVolume * (srcA[i] + srcB[i] + srcC[i])) >> 16 */ 
	
	sub 	r3,r0		/* r0 = mixed - filtered[i-1] */
	muls.w 	r0,r1		/* macl = 203 * (mixed - filtered[i-1]) */
	sts	macl,r0
	shlr8	r0		/* r0 = 203/256 * (mixed - filtered[i-1]) */
	exts.w	r0,r0
	add	#2,r4	
	add	r3,r0
	mov	r0,r3
	add	r12,r0
	dt	r6
	mov.w	r0,@r4		/* filtered[i] = filtered[i-1] + 203/256 * (mixed - filtered[i-1]) */
	bf	filter_loop
	
        mov.l   @r15+,r12
        mov.l   @r15+,r11
        mov.l   @r15+,r10
        mov.l   @r15+,r9
        mov.l   @r15+,r7
	rts
	nop

.align 2
masterVolume: .long _masterVolume
mixFactor: .long _mixFactor
sampleBias: .long _sampleBias