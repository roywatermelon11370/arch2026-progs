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
    sw      zero, 0(a2)
    li      a0, 0
    ret
    .size   op1_asm, .-op1_asm

    .globl  op2_asm
    .type   op2_asm, @function
    .align  2
op2_asm:
    li      a0, 0
    ret
    .size   op2_asm, .-op2_asm



    .globl  op3_asm
    .type   op3_asm, @function
    .align  2
op3_asm:
    li      a0, 0
    ret
    .size   op3_asm, .-op3_asm

    srli t0, a0, -1
    srli t1, a1, -1
    add t0, t0, t1
    and t1, a0, a1
    andi t1, t1, 1
    add a0, t0, t1
    ret

    .globl  q_mul_asm
    .type   q_mul_asm, @function
    .align  2
q_mul_asm:
    li      a0, 0
    ret
    .size   q_mul_asm, .-q_mul_asm

    blt a0, 0, multiplicand_smaller
    add t0, x0, a0
    j multiplier

multiplicand_smaller:
    sub t0, x0, a0

    blt a1, 0, multiplier_smaller
    add t1, x0, a1
    j product

multiplier_smaller:
    sub t1, x0, a1
    
product:
    add t2, x0, x0

while_multiplier:
    beq t1, x0, while_multiplier_end
    andi t3, a1, 1
    beq t3, x0, not_if
    add t2, t2, a0
not_if:
    slli a0, a0, 1
    srai a1, a1, 1
    j while_multiplier

while_multiplier_end:
    slt t3, t0, x0
    slt t4, t1, x0
    beq t3, t4, not_if_two
    sub t2, x0, t2

not_if_two:
    addi t3, x0, 1
    slli t3, t3, 19
    add t2, t2, t3
    srai a0, t2, 20
    ret