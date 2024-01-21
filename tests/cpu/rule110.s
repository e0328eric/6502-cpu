;; Author: Sungbae Jeong
;;
;; NOTE: Rule110 Implementation for 6502 cpu instructions to test my emulator

;; NOTE: Memories that I use in here
;; 1. Actual drawing space is $0200 ~ $05FF.
;; 2. Rule110 cells states are stored in $50 ~ $6F.
;; 3. The space $75, $76, $85, and $86 are used for the special purpose

; store palette address inside
    lda #$02
    ldx #$00
    sta $86
    stx $85
    ldx #$0

; state 1
    lda #$01
    sta $6F
    jsr draw_palette

rule110_loop:
    lda #$DF
    cmp $85
    bcs rule110_loop_1
    lda #$1
    adc $86
    sta $86
    lda #$0
    sta $85
    jmp rule110_loop_2
rule110_loop_1:
    clc
    lda #$20
    adc $85
    sta $85
rule110_loop_2:

    jsr change_state
    jsr draw_palette
    inx
    cpx #$1E
    bcc rule110_loop

    brk

draw_palette:
    pha
    php
    txa
    pha
    ldx #$0
    ldy #$0
draw_palette_loop:
    lda $50, X
    sta ($85), Y
    inx
    iny
    cpx #$20
    bcc draw_palette_loop
    pla
    tax
    plp
    pla
    rts

;; The rule of Rule110 is that looking at
change_state:
    pha
    php
    txa
    pha

    lda #$4F
    sta $75
    lda #$0
    sta $76
    lda #$1
    ldx #$0

change_state_check_loop:
    inc $75
    inx
    lda #$6E
    cmp $75
    beq change_state_ret

    ldy #$0
    lda #$1
    cmp ($75), Y
    beq change_state_check_case1

    iny
    lda ($75), Y
    iny
    ora ($75), Y
    dey
    sta $30, X
    jmp change_state_check_loop

change_state_check_case1:
    iny
    and ($75), Y
    iny
    eor ($75), Y
    dey
    sta $30, X
    jmp change_state_check_loop

change_state_ret:
    lda #$1
    sta $4F
    ldx #$0
change_state_memcpy:
    lda $30, X
    sta $50, X
    inx
    cpx #$20
    bcc change_state_memcpy
    pla
    tax
    plp
    pla
    rts
