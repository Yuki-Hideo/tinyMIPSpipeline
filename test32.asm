# mipstest32.asm
#
# Test MIPS instructions. Assumes memory was
# initialized as:
# word 16: 3 - be careful of endianness
# word 17: 5
# word 18: 12
main:   #Assembly Code          effect                  Machine Code
        lw $2, 68($0)           # initialize $2 = 5     8c020044
        lw $7, 64($0)           # initialize $7 = 3     8c070040
        lw $3, 72($0)           # initialize $3 = 12    8c030048
        or $4, $7, $2           # $4 <= 3 or 5 = 7      00e22025
        and $5, $3, $4          # $5 <= 12 and 7 = 4    00642824
        add $5, $5, $4          # $5 <= 4 + 7 = 11      00a42820
        beq $5, $7, end         # shouldn't be taken    10a70008
        slt $6, $3, $4          # $6 <= 12 < 7 = 0      0064302a
        beq $6, $0, around      # should be taken       10c00001
        lw $5, 0($0)            # shouldn't happen      8c050000
around: slt $6, $7, $2          # $6 <= 3 < 5 = 1       00e2302a
        add $7, $6, $5          # $7 <= 1 + 11 = 12     00c53820
        sub $7, $7, $2          # $7 <= 12 - 5 = 7      00e23822
        j end                   # should be taken       0800000f
        lw $7, 0($0)            # shouldn't happen      8c070000
end:    sw $7, 20($0)           # write adr 20 <=  7    ac070014
        .dw 3                   #                       00000003
        .dw 5                   #                       00000005
        .dw 12                  #                       0000000c
