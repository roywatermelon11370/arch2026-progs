# rubik_solve_asm: optimal 2x2x2 cube solver, hand-written RV32I.
#
# int rubik_solve_asm(const char *state, char *out, size_t cap)
#                                   a0 = state, a1 = out, a2 = cap; result in a0
#
# RV32I and Zicsr only: no mul, div, rem, no floating point, no compressed
# instructions, no heap, no recursion. Tests: tests/trubik.c.

    .text
    .align  2
    .globl  rubik_solve_asm
    .type   rubik_solve_asm, @function
rubik_solve_asm:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    mv      s0, a1                      # out
    mv      s1, a2                      # cap

    # gp and go occupy 0(sp) and 4(sp), rather than caller-saved temporaries.
    add     t0, zero, zero
    add     t1, zero, zero
    sw      t0, 0(sp)
    sw      t1, 4(sp)
if_not_target_parse_state_gp_go:
    addi    a1, sp, 0
    addi    a2, sp, 4
    call    target_parse_asm
    bnez    a0, if_cap_equal_zero
    li      a0, -1
    j       rubik_solve_return

if_cap_equal_zero:
    bnez    s1, if_gp_equal_zero_and_go_equal_zero
    li      a0, -2
    j       rubik_solve_return

if_gp_equal_zero_and_go_equal_zero:
    lw      t0, 0(sp)
    lw      t1, 4(sp)
    or      t2, t0, t1
    bnez    t2, rubik_solve_search
    sb      zero, 0(s0)
    li      a0, 0
    j       rubik_solve_return
rubik_solve_search:
    mv      a0, t0
    mv      a1, t1
    call    solve_coordinates_asm

if_length_smaller_than_zero:
    bgez    a0, rubik_solve_count
    li      a0, -1
    j       rubik_solve_return

    # Check the entire string size before writing anything to out.
rubik_solve_count:
    mv      s2, a0                      # shortest length
    la      t0, rubik_asm_result_path
    add     t1, t0, s2
    la      t2, rubik_move_suffix
    li      t3, 0                       # character count, excluding NUL
rubik_solve_count_loop:
    beq     t0, t1, rubik_solve_check_cap
    lbu     t4, 0(t0)
    add     t4, t2, t4
    lbu     t4, 0(t4)
    sltu    t4, zero, t4
    add     t3, t3, t4
    addi    t3, t3, 2                   # face and one separator
    addi    t0, t0, 1
    j       rubik_solve_count_loop
rubik_solve_check_cap:
    # The extra separator counts the required final NUL instead.
    bltu    s1, t3, rubik_solve_small_buffer
    la      t0, rubik_asm_result_path
    add     t1, t0, s2
    mv      t2, s0
    la      a3, rubik_move_letter
    la      a4, rubik_move_suffix
rubik_solve_write_loop:
    beq     t0, t1, rubik_solve_write_done
    beq     t2, s0, rubik_solve_write_move
    li      t3, 32
    sb      t3, 0(t2)
    addi    t2, t2, 1
rubik_solve_write_move:
    lbu     t3, 0(t0)
    add     t4, a3, t3
    lbu     t4, 0(t4)
    sb      t4, 0(t2)
    addi    t2, t2, 1
    add     t4, a4, t3
    lbu     t4, 0(t4)
    beqz    t4, rubik_solve_write_next
    sb      t4, 0(t2)
    addi    t2, t2, 1
rubik_solve_write_next:
    addi    t0, t0, 1
    j       rubik_solve_write_loop
rubik_solve_write_done:
    sb      zero, 0(t2)
    mv      a0, s2
    j       rubik_solve_return
rubik_solve_small_buffer:
    sb      zero, 0(s0)
    li      a0, -2
rubik_solve_return:
    lw      s2, 16(sp)
    lw      s1, 20(sp)
    lw      s0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    ret
    .size   rubik_solve_asm, .-rubik_solve_asm

# a0 = state, a1 = &gp, a2 = &go; returns 1 for a valid state, otherwise 0.
# gp/go are written only after all input checks succeed.
    .align  2
    .type   target_parse_asm, @function
target_parse_asm:
    mv      t0, a0
    addi    t1, a0, 14
target_parse_length_loop:
    lbu     t2, 0(t0)
    beqz    t2, target_parse_invalid
    addi    t0, t0, 1
    bne     t0, t1, target_parse_length_loop
    lbu     t2, 0(t0)
    bnez    t2, target_parse_invalid

    li      t0, 0                       # i
    li      t1, 0                       # seen cubies
    li      a3, 7
target_parse_cubies_loop:
    add     t2, a0, t0
    lbu     t2, 0(t2)
    addi    t2, t2, -49
    bgeu    t2, a3, target_parse_invalid
    li      t3, 1
    sll     t3, t3, t2
    and     t4, t1, t3
    bnez    t4, target_parse_invalid
    or      t1, t1, t3
    addi    t0, t0, 1
    bne     t0, a3, target_parse_cubies_loop

    li      t6, 0                       # permutation rank
    li      t0, 0                       # i
    la      a3, rubik_rank_weights
target_parse_rank_outer:
    add     t2, a0, t0
    lbu     t3, 0(t2)
    slli    t2, t0, 1
    add     t2, a3, t2
    lhu     a4, 0(t2)
    addi    t1, t0, 1                   # j
target_parse_rank_inner:
    add     t2, a0, t1
    lbu     t2, 0(t2)
    bgeu    t2, t3, target_parse_rank_next
    add     t6, t6, a4
target_parse_rank_next:
    addi    t1, t1, 1
    li      t2, 7
    bne     t1, t2, target_parse_rank_inner
    addi    t0, t0, 1
    li      t2, 6
    bne     t0, t2, target_parse_rank_outer

    addi    a3, a0, 7
    li      t0, 0
    li      t4, 0                       # twist sum modulo 3
    li      t5, 0                       # orientation rank
target_parse_orientation_loop:
    add     t1, a3, t0
    lbu     t1, 0(t1)
    addi    t1, t1, -49
    li      t2, 3
    bgeu    t1, t2, target_parse_invalid
    add     t4, t4, t1
    bltu    t4, t2, target_parse_orientation_rank
    addi    t4, t4, -3
target_parse_orientation_rank:
    li      t2, 6
    beq     t0, t2, target_parse_orientation_next
    slli    t3, t5, 1
    add     t5, t5, t3
    add     t5, t5, t1
target_parse_orientation_next:
    addi    t0, t0, 1
    li      t2, 7
    bne     t0, t2, target_parse_orientation_loop
    bnez    t4, target_parse_invalid
    sw      t6, 0(a1)
    sw      t5, 0(a2)
    li      a0, 1
    ret
target_parse_invalid:
    li      a0, 0
    ret
    .size   target_parse_asm, .-target_parse_asm

# a0 = p, a1 = o; returns the packed near-table entry or -1.
    .align  2
    .type   find_near_asm, @function
find_near_asm:
    slli    t0, a0, 10
    or      t0, t0, a1
    slli    t1, a0, 1
    la      t4, rubik_asm_near_offsets
    add     t1, t4, t1
    lhu     t2, 0(t1)                   # lo
    lhu     t3, 2(t1)                   # hi
    la      t4, rubik_asm_near_solved
find_near_loop:
    bgeu    t2, t3, find_near_missing
    add     t5, t2, t3
    srli    t5, t5, 1
    slli    t6, t5, 2
    add     t6, t4, t6
    lw      a0, 0(t6)
    srli    t6, a0, 7
    bltu    t6, t0, find_near_right
    bltu    t0, t6, find_near_left
    ret
find_near_right:
    addi    t2, t5, 1
    j       find_near_loop
find_near_left:
    mv      t3, t5
    j       find_near_loop
find_near_missing:
    li      a0, -1
    ret
    .size   find_near_asm, .-find_near_asm

# a0 = p, a1 = o; returns whether the exact distance is 11.
    .align  2
    .type   at_distance_eleven_asm, @function
at_distance_eleven_asm:
    slli    t0, a0, 10
    or      t0, t0, a1
    la      t1, rubik_asm_distance_eleven
    li      t2, 0
    li      t3, 2644
at_distance_eleven_loop:
    bgeu    t2, t3, at_distance_eleven_missing
    add     t4, t2, t3
    srli    t4, t4, 1
    slli    t5, t4, 2
    add     t5, t1, t5
    lw      t5, 0(t5)
    bltu    t5, t0, at_distance_eleven_right
    bltu    t0, t5, at_distance_eleven_left
    li      a0, 1
    ret
at_distance_eleven_right:
    addi    t2, t4, 1
    j       at_distance_eleven_loop
at_distance_eleven_left:
    mv      t3, t4
    j       at_distance_eleven_loop
at_distance_eleven_missing:
    li      a0, 0
    ret
    .size   at_distance_eleven_asm, .-at_distance_eleven_asm

# a0 = p, a1 = o, a2 = near entry, a3 = prefix length.
# Appends the exact suffix to result_path and returns the total length.
    .align  2
    .type   finish_path_asm, @function
finish_path_asm:
    addi    sp, sp, -32
    sw      ra, 28(sp)
    sw      s0, 24(sp)
    sw      s1, 20(sp)
    sw      s2, 16(sp)
    sw      s3, 12(sp)
    sw      s4, 8(sp)
    mv      s0, a0
    mv      s1, a1
    srli    s2, a2, 4
    andi    s2, s2, 7
    mv      s3, a3
    la      s4, rubik_asm_result_path
finish_path_loop:
    beqz    s2, finish_path_done
    andi    t0, a2, 15
    add     t1, s4, s3
    sb      t0, 0(t1)
    addi    s3, s3, 1
    la      t1, rubik_move_face
    add     t1, t1, t0
    lbu     t1, 0(t1)
    slli    t1, t1, 2
    la      t2, rubik_pt
    add     t2, t2, t1
    lw      t5, 0(t2)
    la      t2, rubik_ot
    add     t2, t2, t1
    lw      t6, 0(t2)
    la      t1, rubik_move_turns
    add     t1, t1, t0
    lbu     t0, 0(t1)
finish_path_turn_loop:
    slli    t1, s0, 1
    add     t1, t5, t1
    lhu     s0, 0(t1)
    slli    t1, s1, 1
    add     t1, t6, t1
    lhu     s1, 0(t1)
    addi    t0, t0, -1
    bnez    t0, finish_path_turn_loop
    addi    s2, s2, -1
    beqz    s2, finish_path_done
    mv      a0, s0
    mv      a1, s1
    call    find_near_asm
    mv      a2, a0
    j       finish_path_loop
finish_path_done:
    mv      a0, s3
    lw      s4, 8(sp)
    lw      s3, 12(sp)
    lw      s2, 16(sp)
    lw      s1, 20(sp)
    lw      s0, 24(sp)
    lw      ra, 28(sp)
    addi    sp, sp, 32
    ret
    .size   finish_path_asm, .-finish_path_asm

# a0 = p, a1 = o; same iterative-deepening and five-move suffix as rubik.c.
# Frame offsets: p=0, o=4, np=8, no=12, face=16, turn=20, previous=24.
# s0=result_path, s1=frames, s2=bound, s3=last, s4=depth, s5=current frame.
# s6/s7=turn-table pointers, s8/s9=distances, s10/s11=near table/index.
    .align  2
    .type   solve_coordinates_asm, @function
solve_coordinates_asm:
    addi    sp, sp, -80
    sw      ra, 76(sp)
    sw      s0, 72(sp)
    sw      s1, 68(sp)
    sw      s2, 64(sp)
    sw      s3, 60(sp)
    sw      s4, 56(sp)
    sw      s5, 52(sp)
    sw      s6, 48(sp)
    sw      s7, 44(sp)
    sw      s8, 40(sp)
    sw      s9, 36(sp)
    sw      s10, 32(sp)
    sw      s11, 28(sp)
    sw      a0, 0(sp)
    sw      a1, 4(sp)
    la      s0, rubik_asm_result_path
    la      s1, rubik_asm_frames
    la      s6, rubik_pt
    la      s7, rubik_ot
    la      s8, rubik_asm_permutation_distance
    la      s9, rubik_asm_orientation_distance
    la      s10, rubik_asm_near_solved
    la      s11, rubik_asm_near_offsets
    call    find_near_asm
    li      t0, -1
    beq     a0, t0, solve_coordinates_check_eleven
    mv      a2, a0
    lw      a0, 0(sp)
    lw      a1, 4(sp)
    li      a3, 0
    call    finish_path_asm
    j       solve_coordinates_return
solve_coordinates_check_eleven:
    lw      a0, 0(sp)
    lw      a1, 4(sp)
    call    at_distance_eleven_asm
    li      s2, 11
    li      s3, 11
    bnez    a0, solve_coordinates_bound_loop
    li      s2, 6
    li      s3, 10
    lw      t0, 0(sp)
    add     t0, s8, t0
    lbu     t0, 0(t0)
    bleu    t0, s2, solve_coordinates_orientation_bound
    mv      s2, t0
solve_coordinates_orientation_bound:
    lw      t0, 4(sp)
    add     t0, s9, t0
    lbu     t0, 0(t0)
    bleu    t0, s2, solve_coordinates_bound_loop
    mv      s2, t0
solve_coordinates_bound_loop:
    bltu    s3, s2, solve_coordinates_failed
    li      s4, 0
    mv      s5, s1
    lw      t0, 0(sp)
    lw      t1, 4(sp)
    sw      t0, 0(s5)
    sw      t1, 4(s5)
    sw      t0, 8(s5)
    sw      t1, 12(s5)
    sw      zero, 16(s5)
    sw      zero, 20(s5)
    li      t0, 3
    sw      t0, 24(s5)
solve_coordinates_search_loop:
    lw      t0, 16(s5)                  # face
    li      t1, 3
    beq     t0, t1, solve_coordinates_backtrack
    lw      t1, 24(s5)
    beq     t0, t1, solve_coordinates_skip_face

    slli    t4, t0, 2
    add     t5, s6, t4
    lw      t5, 0(t5)
    add     t6, s7, t4
    lw      t6, 0(t6)
    lw      t2, 8(s5)
    lw      t3, 12(s5)
    slli    t2, t2, 1
    slli    t3, t3, 1
    add     t2, t5, t2
    add     t3, t6, t3
    lhu     a0, 0(t2)                   # np
    lhu     a1, 0(t3)                   # no
    lw      t2, 20(s5)                  # old turn
    addi    t3, t2, 1
    li      t4, 3
    bne     t3, t4, solve_coordinates_continue_turn
    addi    t3, t0, 1
    sw      t3, 16(s5)
    sw      zero, 20(s5)
    lw      t3, 0(s5)
    lw      t4, 4(s5)
    sw      t3, 8(s5)
    sw      t4, 12(s5)
    j       solve_coordinates_check_distance
solve_coordinates_continue_turn:
    sw      t3, 20(s5)
    sw      a0, 8(s5)
    sw      a1, 12(s5)
solve_coordinates_check_distance:
    sub     t3, s2, s4
    addi    t3, t3, -1                  # remaining
    add     t4, s8, a0
    lbu     t4, 0(t4)
    bltu    t3, t4, solve_coordinates_search_loop
    add     t4, s9, a1
    lbu     t4, 0(t4)
    bltu    t3, t4, solve_coordinates_search_loop
    slli    t4, t0, 1
    add     t4, t4, t0
    add     t4, t4, t2
    add     t5, s0, s4
    sb      t4, 0(t5)
    li      t4, 5
    beq     t3, t4, solve_coordinates_find_near

    addi    s4, s4, 1
    addi    s5, s5, 32
    sw      a0, 0(s5)
    sw      a1, 4(s5)
    sw      a0, 8(s5)
    sw      a1, 12(s5)
    sw      zero, 16(s5)
    sw      zero, 20(s5)
    sw      t0, 24(s5)
    j       solve_coordinates_search_loop
solve_coordinates_skip_face:
    addi    t0, t0, 1
    sw      t0, 16(s5)
    j       solve_coordinates_search_loop
solve_coordinates_backtrack:
    beqz    s4, solve_coordinates_next_bound
    addi    s4, s4, -1
    addi    s5, s5, -32
    j       solve_coordinates_search_loop
solve_coordinates_next_bound:
    addi    s2, s2, 1
    j       solve_coordinates_bound_loop

    # Inline find_near's leaf loop to retain np/no and reuse table bases.
solve_coordinates_find_near:
    slli    a2, a0, 10
    or      a2, a2, a1
    slli    t0, a0, 1
    add     t0, s11, t0
    lhu     t1, 0(t0)
    lhu     t2, 2(t0)
solve_coordinates_near_loop:
    bgeu    t1, t2, solve_coordinates_search_loop
    add     t3, t1, t2
    srli    t3, t3, 1
    slli    t4, t3, 2
    add     t4, s10, t4
    lw      t5, 0(t4)
    srli    t6, t5, 7
    bltu    t6, a2, solve_coordinates_near_right
    bltu    a2, t6, solve_coordinates_near_left
    mv      a2, t5
    addi    a3, s4, 1
    call    finish_path_asm
    j       solve_coordinates_return
solve_coordinates_near_right:
    addi    t1, t3, 1
    j       solve_coordinates_near_loop
solve_coordinates_near_left:
    mv      t2, t3
    j       solve_coordinates_near_loop
solve_coordinates_failed:
    li      a0, -1
solve_coordinates_return:
    lw      s11, 28(sp)
    lw      s10, 32(sp)
    lw      s9, 36(sp)
    lw      s8, 40(sp)
    lw      s7, 44(sp)
    lw      s6, 48(sp)
    lw      s5, 52(sp)
    lw      s4, 56(sp)
    lw      s3, 60(sp)
    lw      s2, 64(sp)
    lw      s1, 68(sp)
    lw      s0, 72(sp)
    lw      ra, 76(sp)
    addi    sp, sp, 80
    ret
    .size   solve_coordinates_asm, .-solve_coordinates_asm

    .section .rodata
    .align  2
rubik_pt:
    .word   rubik_asm_permutation_turns
    .word   rubik_asm_permutation_turns + 10080
    .word   rubik_asm_permutation_turns + 20160
rubik_ot:
    .word   rubik_asm_orientation_turns
    .word   rubik_asm_orientation_turns + 1458
    .word   rubik_asm_orientation_turns + 2916
rubik_rank_weights:
    .half   720, 120, 24, 6, 2, 1
rubik_move_face:
    .byte   0, 0, 0, 1, 1, 1, 2, 2, 2
rubik_move_turns:
    .byte   1, 2, 3, 1, 2, 3, 1, 2, 3
rubik_move_letter:
    .byte   82, 82, 82, 66, 66, 66, 68, 68, 68
rubik_move_suffix:
    .byte   0, 50, 39, 0, 50, 39, 0, 50, 39

    .section .bss
    .align  2
rubik_asm_result_path:
    .zero   11
    .align  2
rubik_asm_frames:
    .zero   192
