# op1, op2, op3 and q_mul: hand-written RV32I.
#
# uint32_t op1_asm(uint32_t a, uint32_t b, int *n)   a0, a1, a2 -> a0
# uint32_t op2_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# uint32_t op3_asm(uint32_t a, uint32_t b)           a0, a1 -> a0
# int32_t  q_mul_asm(int32_t a, int32_t b)           a0, a1 -> a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions. q_mul forms a 64-bit product in a register pair. Tests:
# tests/tfixed.c.

    .text

    .globl  op1_asm
    .type   op1_asm, @function
    .align  2
op1_asm:
    # t0 = carry, t1 = n
    add t1, x0, x0
    beq a1, x0, while_b_end

while_b:
    and t0, a0, a1
    slli t0, t0, 1
    xor a0, a0, a1
    add a1, x0, t0
    addi t1, t1, 1
    bne a1, x0, while_b

while_b_end:
    sw t1, 0(a2)
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    # The contract requires a straight-line subtraction.
    sub a0, a0, a1
    ret
    .size   op2_asm, .-op2_asm

    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    # t0 = half sums, t1 = shared low bit
    srli t0, a0, 1
    srli t1, a1, 1
    add t0, t0, t1
    and t1, a0, a1
    andi t1, t1, 1
    add a0, t0, t1
    ret
    .size   op3_asm, .-op3_asm

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    # t4:t0 = multiplicand, t1 = multiplier, t5:t2 = product
    # t3 and t6 = temporary values; a0 and a1 retain the original signs.
    blt a0, x0, multiplicand_smaller
    add t0, x0, a0
    j multiplier

multiplicand_smaller:
    sub t0, x0, a0

multiplier:
    blt a1, x0, multiplier_smaller
    add t1, x0, a1
    j product

multiplier_smaller:
    sub t1, x0, a1

product:
    add t2, x0, x0
    add t4, x0, x0
    add t5, x0, x0
    beq t1, x0, while_multiplier_end

while_multiplier:
    andi t3, t1, 1
    beq t3, x0, not_if
    # Add both halves and carry the low-word overflow into the high word.
    add t2, t2, t0
    sltu t6, t2, t0
    add t5, t5, t4
    add t5, t5, t6
not_if:
    srli t3, t0, 31
    slli t0, t0, 1
    slli t4, t4, 1
    or t4, t4, t3
    srli t1, t1, 1
    bne t1, x0, while_multiplier

while_multiplier_end:
    xor t3, a0, a1
    bge t3, x0, not_if_two
    # Negate the 64-bit product, including the borrow from the low word.
    sltu t6, x0, t2
    sub t2, x0, t2
    sub t5, x0, t5
    sub t5, t5, t6

not_if_two:
    lui t3, 0x80
    add t2, t2, t3
    sltu t6, t2, t3
    add t5, t5, t6
    # Keep bits 20 through 51 of the rounded product.
    srli t2, t2, 20
    slli t5, t5, 12
    or a0, t2, t5
    ret
    .size   q_mul_asm, .-q_mul_asm
