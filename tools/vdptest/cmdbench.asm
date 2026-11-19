; CMDBENCH for MSX2 - duration of V9938/V9958 commands in SCREEN 5
;
; Copyright (c) 2026 Molekula
; SPDX-License-Identifier: GPL-3.0-or-later
;
; 16 kB cartridge ROM at 4000h. Measures eight commands in SCREEN 5 with NTSC / PAL, 212 / 192
; lines, sprites on / off and the display off, then in SCREEN 6, 7 and 8. Reference: openMSX
; (cmdbench.tcl, rtl/peripheral/VIDEO/VDP/tb/cmdbench_openmsx.txt).
;
; Every command starts one line before the display (VR 1 -> 0). A result is the number of polling
; iterations from the command start to CE = 0, 56 T each
; (same loop as vdptest page 8): lines = iterations * 56 / 228. 65280 = timeout.
; Results: C000h, 14 configurations x 8 words; C0FEh = 0A5h when done. Then shown in
; 80 columns (one configuration per row).

VDPC    EQU     99h
VDPI    EQU     9Bh
INITXT  EQU     006Ch           ; BIOS
LINL40  EQU     0F3AEh

RESULT  EQU     0C000h
DONE    EQU     0C0FEh
CURPOS  EQU     0C0F0h          ; PUTC cursor
NCMD    EQU     8
NCFG    EQU     14

        ORG     4000h
        DB      "AB"
        DW      START
        DW      0, 0, 0
        DS      6, 0

START:  DI
        LD      SP, 0EF00h
        XOR     A
        LD      (DONE), A
        LD      HL, SCR5            ; SCREEN 5, SAT at 7600h with Y = 216 (no sprite shown)
        CALL    REGS
        LD      A, 2                ; S#2: CE and VR
        LD      E, 15
        CALL    WRREG
        LD      IX, CFGTAB
        LD      IY, RESULT
        LD      B, NCFG
CF1:    PUSH    BC
        LD      A, (IX + 0)         ; R#0 (screen mode)
        LD      E, 0
        CALL    WRREG
        LD      A, (IX + 1)         ; R#1
        LD      E, 1
        CALL    WRREG
        LD      A, (IX + 2)         ; R#8
        LD      E, 8
        CALL    WRREG
        LD      A, (IX + 3)         ; R#9
        LD      E, 9
        CALL    WRREG
        LD      HL, 7600h           ; SAT: Y = 216 (no sprite), in the address layout of the mode
        CALL    VADDR
        LD      A, 0D8h
        OUT     (98h), A
        LD      HL, CMDTAB
        LD      B, NCMD
CF2:    PUSH    BC
        CALL    CMDRUN              ; HL -> next entry, DE = iterations
        LD      (IY + 0), E
        LD      (IY + 1), D
        INC     IY
        INC     IY
        POP     BC
        DJNZ    CF2
        LD      DE, 4
        ADD     IX, DE
        POP     BC
        DJNZ    CF1
        XOR     A
        LD      E, 15
        CALL    WRREG
        LD      A, 0A5h
        LD      (DONE), A

        LD      A, 80               ; show the results, 80 columns
        LD      (LINL40), A
        CALL    INITXT
        DI
        LD      A, 0                ; VRAM 0xxxxh for PUTC
        LD      E, 14
        CALL    WRREG
        LD      HL, 0
        LD      (CURPOS), HL
        LD      HL, TITLE
        CALL    PRINT
        LD      IY, RESULT
        LD      IX, CFGTXT
        LD      B, NCFG
SH1:    PUSH    BC
        PUSH    IX
        POP     HL
        CALL    PRINT
        PUSH    HL
        POP     IX
        LD      B, NCMD
SH2:    PUSH    BC
        LD      L, (IY + 0)
        LD      H, (IY + 1)
        INC     IY
        INC     IY
        CALL    PRNUM
        POP     BC
        DJNZ    SH2
        LD      A, 13
        CALL    PUTC
        LD      A, 10
        CALL    PUTC
        POP     BC
        DJNZ    SH1
        JR      $

; run the command at HL (R#32-R#46, 15 bytes), HL += 16; DE = iterations until CE = 0.
; R#46 is written when VR goes 0 (one line before the display), so every run starts at the
; same place of the frame. S#2 must be selected.
CMDRUN: PUSH    HL
        LD      A, 32
        LD      E, 17
        CALL    WRREG
        POP     HL
        LD      BC, 14 * 256 + VDPI
        OTIR
WV1:    IN      A, (VDPC)
        AND     40h
        JR      Z, WV1
WV0:    IN      A, (VDPC)
        AND     40h
        JR      NZ, WV0
        LD      A, (HL)             ; R#46
        OUT     (VDPI), A
        INC     HL
        INC     HL
        PUSH    HL
        LD      HL, 0
CNT:    IN      A, (VDPC)           ; 56 T per iteration
        AND     01h
        JR      Z, CNT9
        INC     HL
        LD      A, H
        INC     A
        JP      NZ, CNT
CNT9:   EX      DE, HL
        POP     HL
        RET

; A = value, E = register
WRREG:  OUT     (VDPC), A
        LD      A, E
        OR      80h
        OUT     (VDPC), A
        RET

; HL = register / value pairs, FFh ends
REGS:   LD      E, (HL)
        LD      A, E
        INC     A
        RET     Z
        INC     HL
        LD      A, (HL)
        INC     HL
        CALL    WRREG
        JR      REGS

; VRAM write address HL (A16-A14 = 0 for 7600h: R#14 = 1)
VADDR:  LD      A, 1
        LD      E, 14
        CALL    WRREG
        LD      A, L
        OUT     (VDPC), A
        LD      A, H
        AND     3Fh
        OR      40h
        OUT     (VDPC), A
        RET

; character A into the TEXT2 name table (0000h) at CURPOS; 13 = start of the next row,
; other control characters are ignored. Keeps all registers but AF.
PUTC:   PUSH    HL
        PUSH    DE
        LD      HL, (CURPOS)
        CP      13
        JR      Z, PC2
        CP      32
        JR      C, PC9
        LD      E, A
        DI
        LD      A, L
        OUT     (VDPC), A
        LD      A, H
        OR      40h
        OUT     (VDPC), A
        LD      A, E
        OUT     (98h), A
        INC     HL
        JR      PC8
PC2:    LD      DE, 80              ; next row
PC3:    OR      A
        SBC     HL, DE
        JR      NC, PC3
        ADD     HL, DE              ; HL = column
        EX      DE, HL
        LD      HL, (CURPOS)
        OR      A
        SBC     HL, DE
        LD      DE, 80
        ADD     HL, DE
PC8:    LD      (CURPOS), HL
PC9:    POP     DE
        POP     HL
        RET

; print the zero terminated string at HL, HL -> after it
PRINT:  LD      A, (HL)
        INC     HL
        OR      A
        RET     Z
        CALL    PUTC
        JR      PRINT

; HL as 6 columns, right aligned
PRNUM:  LD      A, ' '
        CALL    PUTC
        LD      C, 0                ; 1 = a digit printed
        LD      DE, 10000
        CALL    DIGIT
        LD      DE, 1000
        CALL    DIGIT
        LD      DE, 100
        CALL    DIGIT
        LD      DE, 10
        CALL    DIGIT
        LD      A, L
        ADD     A, '0'
        JP      PUTC
DIGIT:  LD      A, 2Fh              ; '0' - 1 (pasmo makes FFh of the expression)
DG1:    INC     A
        OR      A
        SBC     HL, DE
        JR      NC, DG1
        ADD     HL, DE
        CP      '0'
        JR      NZ, DG2
        BIT     0, C
        JR      NZ, DG2
        LD      A, ' '
        JP      PUTC
DG2:    LD      C, 1
        JP      PUTC

; SCREEN 5: patterns 0000h, SAT 7600h, sprite patterns 7800h, VRAM 128 kB
SCR5:   DB      0, 06h, 1, 00h, 2, 1Fh, 5, 0EFh, 11, 0, 6, 0Fh, 7, 04h, 8, 08h
        DB      9, 0, 14, 0, 15, 0, 23, 0, 0FFh

; R#0, R#1, R#8, R#9 (the first ten: the configurations of the old ESE wait tables 601-605, 501-505)
CFGTAB: DB      06h, 40h, 08h, 80h  ; NTSC 212, sprites on
        DB      06h, 40h, 08h, 00h  ; NTSC 192, sprites on
        DB      06h, 40h, 0Ah, 80h  ; NTSC 212, sprites off
        DB      06h, 40h, 0Ah, 00h  ; NTSC 192, sprites off
        DB      06h, 00h, 08h, 80h  ; NTSC, display off
        DB      06h, 40h, 08h, 82h  ; PAL 212, sprites on
        DB      06h, 40h, 08h, 02h  ; PAL 192, sprites on
        DB      06h, 40h, 0Ah, 82h  ; PAL 212, sprites off
        DB      06h, 40h, 0Ah, 02h  ; PAL 192, sprites off
        DB      06h, 00h, 08h, 82h  ; PAL, display off
        DB      08h, 40h, 08h, 80h  ; SCREEN 6, NTSC 212, sprites on
        DB      0Ah, 40h, 08h, 80h  ; SCREEN 7
        DB      0Eh, 40h, 08h, 80h  ; SCREEN 8
        DB      0Eh, 40h, 0Ah, 80h  ; SCREEN 8, sprites off

; SX, SY, DX, DY, NX, NY (words), CLR, ARG, CMD, pad
CMDTAB: DW      0, 0, 0, 0, 256, 106
        DB      44h, 0, 0C0h, 0     ; HMMV
        DW      0, 0, 0, 0, 256, 106
        DB      05h, 0, 80h, 0      ; LMMV
        DW      0, 50, 0, 0, 0, 0
        DB      05h, 02h, 60h, 0    ; SRCH row 50 for a colour other than 5: to the edge
        DW      0, 256, 0, 0, 256, 106
        DB      0, 0, 0E0h, 0       ; YMMM
        DW      0, 256, 0, 0, 256, 106
        DB      0, 0, 0D0h, 0       ; HMMM
        DW      0, 256, 0, 0, 256, 106
        DB      0, 0, 90h, 0        ; LMMM
        DW      0, 0, 0, 0, 255, 100
        DB      0Fh, 0, 70h, 0      ; LINE 255 x 100
        DW      0, 0, 0, 0, 255, 255
        DB      0Fh, 0, 70h, 0      ; LINE 255 x 255

TITLE:  DB      "CMDBENCH (ITERATIONS OF 56 T)", 13, 10
        DB      "                 "
        DB      "  HMMV  LMMV  SRCH  YMMM  HMMM  LMMM LN100 LN255", 13, 10, 0
CFGTXT: DB      "NTSC 212 SPR ON  ", 0
        DB      "NTSC 192 SPR ON  ", 0
        DB      "NTSC 212 SPR OFF ", 0
        DB      "NTSC 192 SPR OFF ", 0
        DB      "NTSC DISPLAY OFF ", 0
        DB      "PAL  212 SPR ON  ", 0
        DB      "PAL  192 SPR ON  ", 0
        DB      "PAL  212 SPR OFF ", 0
        DB      "PAL  192 SPR OFF ", 0
        DB      "PAL  DISPLAY OFF ", 0
        DB      "SCR6 NTSC 212 ON ", 0
        DB      "SCR7 NTSC 212 ON ", 0
        DB      "SCR8 NTSC 212 ON ", 0
        DB      "SCR8 NTSC 212 OFF", 0

        DS      8000h - $, 0FFh
