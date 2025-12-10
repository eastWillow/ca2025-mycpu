# From https://github.com/eastWillow/ca2025-quizzes/tree/Add-rv32emu-Compatibility/q2-problemA
    .data
obdata:     .byte   0x3c, 0x3b, 0x3a
# str1:
#     .ascii  "Move Disk "
#     .set str1_size, .-str1
# str2:
#     .ascii  " from "
#     .set str2_size, .-str2
# str3:
#     .ascii  " to "
#     .set str3_size, .-str3
# endl:
#     .ascii  "\n"
#     .set endl_size, .-endl

    .text
    # .globl  main
    # .type main, @function
    # .extern printstr
    # .extern print_dec
.section .text.init
.globl _start
_start:
    addi    sp, sp, -32
    sw      s0, 0(sp)
    sw      s1, 4(sp)
    sw      s2, 8(sp)
    sw      s3, 12(sp)
    sw      s4, 16(sp)

    li      t0, 0x15
    sw      t0, 20(sp)
    sw      t0, 24(sp)
    sw      t0, 28(sp)
    li      s5, 0x00 # Initial Memory Address

    # Fix disk positions (BLANK 1-3: neutralize t0 effect)
    # BLANK 1: Fix position at sp+20
    sw      x0, 20(sp)

    # BLANK 2: Fix position at sp+24
    sw      x0, 24(sp)

    # BLANK 3: Fix position at sp+28
    sw      x0, 28(sp)

    addi    s0, x0, 1
game_loop:
    # BLANK 4: Check loop termination (2^3 moves)
    addi    t0, x0, 8
    beq     s0, t0, finish_game

    # Gray code formula: gray(n) = n XOR (n >> k)
    # BLANK 5: What is k for Gray code?
    srli    t0, s0, 1

    # BLANK 6: Complete Gray(n) calculation
    xor     t1, s0, t0

    # BLANK 7-8: Calculate previous value and its shift
    addi    t2, s0, -1
    srli    t3, t2, 1

    # BLANK 9: Generate Gray(n-1)
    xor     t2, t2, t3

    # BLANK 10: Which bits changed?
    xor     t0, t1, t2

    # Initialize disk number
    addi    s1, x0, 0

    # BLANK 11: Mask for testing LSB
    andi    t1, t0, 1

    # BLANK 12: Branch if disk 0 moves
    bne     t1, x0, disk_found

    # BLANK 13: Set disk 1
    addi    s1, x0, 1

    # BLANK 14: Test second bit with proper mask
    andi    t1, t0, 2
    bne     t1, x0, disk_found

    # BLANK 15: Last disk number
    addi    s1, x0, 2

disk_found:
    # BLANK 16: Check impossible pattern (multiple bits)
    andi    t5, t0, 5
    addi    t6, x0, 5
    beq     t5, t6, pattern_match
    jal     x0, continue_move
pattern_match:
continue_move:

    # BLANK 17: Word-align disk index (multiply by what?)
    slli    t0, s1, 2

    # BLANK 18: Base offset for disk array
    addi    t0, t0, 20
    add     t0, sp, t0
    lw      s2, 0(t0)

    bne     s1, x0, handle_large

    # BLANK 19: Small disk moves by how many positions?
    addi    s3, s2, 2

    # BLANK 20: Number of pegs
    addi    t1, x0, 3
    blt     s3, t1, display_move
    sub     s3, s3, t1
    jal     x0, display_move

handle_large:
    # BLANK 21: Load reference disk position
    lw      t1, 20(sp)

    # BLANK 22: Sum of all peg indices (0+1+2)
    addi    s3, x0, 3
    sub     s3, s3, s2
    sub     s3, s3, t1

display_move:
    la      s4, obdata
    add     t0, s4, s2

    # BLANK 23: Load byte from obfuscated data
    lbu     t3, 0(t0)
    # BLANK 24: Decode constant (0x6F)
    li      t1, 0x6F
    xor     t3, t3, t1
    # BLANK 25: Final offset adjustment
    addi    t3, t3, -0x12

    add     t2, s4, s3
    lbu     t4, 0(t2)
    xor     t4, t4, t1
    addi    t4, t4, -0x12

    # la      a0, str1      # address of string
    # li      a1, str1_size  # length of string
    # call    printstr

    addi    a0, s1, 1
    sb      a0, 0(s5)       # Save the Disk number to mem(7,0)
    # call    print_dec

    # la      a0, str2      # address of string
    # li      a1, str2_size  # length of string
    # call    printstr

    addi    a0, t3, 0
    sb      a0, 1(s5)       # Save the From. Column ASCII to mem(15,8)
    # call    print_char

    # la      a0, str3      # address of string
    # li      a1, str3_size  # length of string
    # call    printstr

    addi    a0, t4, 0
    sb      a0, 2(s5)       # Save the Dest. Column ASCII to mem(23,16)
    # call    print_char

    # la      a0, endl      # address of string
    # li      a1, endl_size  # length of string
    # call    printstr

    # BLANK 26: Calculate storage offset
    slli    t0, s1, 2
    addi    t0, t0, 20
    add     t0, sp, t0
    addi    s5, s5, 4
    # BLANK 27: Update disk position
    sw      s3, 0(t0)

    # BLANK 28-29: Increment counter and loop
    addi    s0, s0, 1
    jal     x0, game_loop

finish_game:
    lw      s0, 0(sp)
    lw      s1, 4(sp)
    lw      s2, 8(sp)
    lw      s3, 12(sp)
    lw      s4, 16(sp)
    # li      a7, 93    # exit syscall number
    # li      a0, 0     # exit code
    # ecall

loop:
    j loop
