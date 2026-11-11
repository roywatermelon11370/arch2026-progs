# BFloat16 routines: hand-written RV32I.
#
# uint16_t bf16_from_f32_asm(uint32_t f32bits)   a0 -> a0
# uint16_t bf16_mul_asm(uint16_t a, uint16_t b)  a0, a1 -> a0
# uint16_t bf16_sqrt_asm(uint16_t a)             a0 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. Tests: tests/tbf16.c.

    .text

    .globl  bf16_from_f32_asm
    .type   bf16_from_f32_asm, @function
    .align  2
bf16_from_f32_asm:
    # Infinity and NaN skip rounding.
    srli    t0, a0, 23
    andi    t0, t0, 0xff
    li      t1, 0xff
    beq     t0, t1, .Lf32_pack

    # Add 0x7fff plus the low bit of the kept half for ties-to-even.
    srli    t0, a0, 16
    andi    t0, t0, 1
    li      t1, 0x7fff
    add     t0, t0, t1
    add     a0, a0, t0
.Lf32_pack:
    srli    a0, a0, 16
    ret
    .size   bf16_from_f32_asm, .-bf16_from_f32_asm

    .globl  bf16_mul_asm
    .type   bf16_mul_asm, @function
    .align  2

bf16_mul_asm:
    # t0 holds the product sign. Keep a0 and a1 for NaN propagation.
    li      t3, 0x7fff
    and     t1, a0, t3
    and     t2, a1, t3
    xor     t0, a0, a1
    srli    t0, t0, 15
    slli    t0, t0, 15

    # Examine a first, even if b is also a NaN or infinity.
    li      t3, 0x7f80
    bgeu    t1, t3, .Lmul_special_a
    bgeu    t2, t3, .Lmul_special_b
    beqz    t1, .Lmul_return_sign
    beqz    t2, .Lmul_return_sign

    # t1 and t2 become the significands, t3 the biased product exponent.
    srli    t4, t1, 7
    srli    t5, t2, 7
    andi    t1, t1, 0x7f
    andi    t2, t2, 0x7f
    add     t3, t4, t5
    addi    t3, t3, -127
    beqz    t4, .Lmul_denormal_a
    ori     t1, t1, 0x80
.Lmul_unpack_b:
    beqz    t5, .Lmul_denormal_b
    ori     t2, t2, 0x80

.Lmul_product:
    # Account for b's leading 1 first, then multiply its low seven bits.
    slli    t4, t1, 7
    andi    t2, t2, 0x7f
    beqz    t2, .Lmul_normalize_product
.Lmul_shift_add:
    andi    t5, t2, 1
    beqz    t5, .Lmul_next_bit
    add     t4, t4, t1
.Lmul_next_bit:
    slli    t1, t1, 1
    srli    t2, t2, 1
    bnez    t2, .Lmul_shift_add

.Lmul_normalize_product:
    srli    t5, t4, 15
    beqz    t5, .Lmul_pack
    srli    t4, t4, 1
    addi    t3, t3, 1
.Lmul_pack:
    slti    t5, t3, 0xff
    beqz    t5, .Lmul_overflow
    srli    t4, t4, 7
    andi    t4, t4, 0x7f
    blez    t3, .Lmul_denormal_result
    slli    t3, t3, 7
    or      t4, t4, t3
    or      a0, t0, t4
    ret

    # A denormal starts at exponent field 1 with no implicit leading bit.
.Lmul_denormal_a:
    addi    t3, t3, 1
.Lmul_shift_a:
    slli    t1, t1, 1
    addi    t3, t3, -1
    andi    t6, t1, 0x80
    beqz    t6, .Lmul_shift_a
    j       .Lmul_unpack_b

.Lmul_denormal_b:
    addi    t3, t3, 1
.Lmul_shift_b:
    slli    t2, t2, 1
    addi    t3, t3, -1
    andi    t6, t2, 0x80
    beqz    t6, .Lmul_shift_b
    j       .Lmul_product

.Lmul_denormal_result:
    # Shift only the stored fraction, as required by the C implementation.
    slti    t5, t3, -6
    bnez    t5, .Lmul_return_sign
    li      t5, 1
    sub     t5, t5, t3
    srl     t4, t4, t5
    or      a0, t0, t4
    ret

.Lmul_special_a:
    bne     t1, t3, .Lmul_return_a
    beqz    t2, .Lmul_invalid
    j       .Lmul_return_infinity
.Lmul_special_b:
    beq     t2, t3, .Lmul_infinity_b
    mv      a0, a1
.Lmul_return_a:
    ret
.Lmul_infinity_b:
    beqz    t1, .Lmul_invalid
    j       .Lmul_return_infinity

.Lmul_return_sign:
    mv      a0, t0
    ret
.Lmul_overflow:
    li      t3, 0x7f80
.Lmul_return_infinity:
    or      a0, t0, t3
    ret
.Lmul_invalid:
    li      a0, 0x7fc0
    ret
    .size   bf16_mul_asm, .-bf16_mul_asm

    .globl  bf16_sqrt_asm
    .type   bf16_sqrt_asm, @function
    .align  2
bf16_sqrt_asm:
    srli    t0, a0, 7
    andi    t0, t0, 0xff
    li      t1, 0xff
    beq     t0, t1, .Lsqrt_special
    srli    t1, a0, 15
    bnez    t1, .Lsqrt_negative
    beqz    t0, .Lsqrt_zero

    # E + 127 has the parity of the unbiased exponent E - 127.
    # Halving E + 127 gives the biased result exponent.
    addi    t0, t0, 127
    andi    t1, a0, 0x7f
    ori     t1, t1, 0x80
    andi    t2, t0, 1
    sll     t1, t1, t2
    srli    t0, t0, 1

    # floor(mid * mid / 128) <= m iff mid * mid <= 128*m + 127.
    # Find the integer square root of that bound one bit at a time.
    slli    t2, t1, 7
    addi    t2, t2, 127
    li      t3, 0
    li      t4, 0x4000
.Lsqrt_digit:
    # t2 is the remainder; t3 holds the scaled partial root.
    add     t5, t3, t4
    srli    t3, t3, 1
    bltu    t2, t5, .Lsqrt_next_digit
    sub     t2, t2, t5
    add     t3, t3, t4
.Lsqrt_next_digit:
    srli    t4, t4, 2
    bnez    t4, .Lsqrt_digit

    slli    t0, t0, 7
    andi    t3, t3, 0x7f
    or      a0, t0, t3
.Lsqrt_return:
    ret

.Lsqrt_special:
    andi    t1, a0, 0x7f
    bnez    t1, .Lsqrt_return
    srli    t1, a0, 15
    beqz    t1, .Lsqrt_return
    j       .Lsqrt_invalid
.Lsqrt_negative:
    slli    t1, a0, 17
    beqz    t1, .Lsqrt_zero
.Lsqrt_invalid:
    li      a0, 0x7fc0
    ret
.Lsqrt_zero:
    li      a0, 0
    ret
    .size   bf16_sqrt_asm, .-bf16_sqrt_asm
