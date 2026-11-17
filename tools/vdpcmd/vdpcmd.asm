; VDPCMD ROM - bengalack's vdpcmd (V9938/V9958 command engine speed) without MSX-DOS
;
; Copyright (c) 2026 Molekula
; SPDX-License-Identifier: GPL-3.0-or-later
; upstream/vdpcmd.com: Copyright (c) 2026 bengalack, MIT License (upstream/LICENSE),
; https://github.com/bengalack/vdpcmd
;
; 16 kB cartridge ROM at 4000h. Copies vdpcmd.com unchanged to RAM at 0100h and runs it with
; the part of the MSX-DOS environment it uses:
;   - RAM in pages 0-3 (the slot of page 3), its data reaches 4817h;
;   - 0038h: JP to an interrupt handler (vdpcmd hooks its own ISR at 0039h);
;   - 000Ch RDSLT, 001Ch CALSLT: page 0 switched to the main BIOS for the call;
;   - 0005h BDOS: any call ends the program.
; Then the ROM waits for SPACE and runs it again.
;
; Build: build.sh (pasmo).

EXPTBL  EQU     0FCC1h          ; main BIOS slot, expanded flags
SNSMAT  EQU     0141h
CHPUT   EQU     00A2h
RDSLT   EQU     000Ch
KEYINT  EQU     0038h

ENV     EQU     0E000h          ; resident part (page 3)
STACK   EQU     0F000h
TPA     EQU     0100h
CLREND  EQU     ENV             ; RAM cleared up to here after loading

        ORG     4000h
        DB      "AB"
        DW      START
        DW      0, 0, 0
        DS      6, 0

START:  DI
        LD      SP, STACK
        LD      HL, ENVSRC
        LD      DE, ENV
        LD      BC, ENVLEN
        LDIR
        CALL    SLOTS
RUN:    DI
        LD      SP, STACK
        JP      LOADRUN

; Slot configurations (H = A8h, L = subslot register of the page 3 slot)
SLOTS:  IN      A, (0A8h)
        LD      (CFGORG + 1), A
        RLCA
        RLCA
        AND     3               ; primary slot of page 3
        LD      C, A
        LD      B, 0
        LD      HL, EXPTBL
        ADD     HL, BC
        LD      A, (HL)
        AND     80h
        LD      (EXPD), A
        LD      A, (0FFFFh)
        CPL
        LD      (CFGORG), A     ; meaningful only when expanded
        RLCA
        RLCA
        AND     3               ; subslot of page 3
        CALL    MUL55
        LD      (CFGRAM), A
        LD      A, C
        CALL    MUL55
        LD      (CFGRAM + 1), A
        LD      C, 0Ch          ; page 1 from the start (ROM), page 0 RAM
        CALL    MIX
        LD      (CFGLOAD), HL
        LD      C, 03h          ; page 0 from the start (BIOS), page 1 RAM
        CALL    MIX
        LD      (CFGP0B), HL
        RET

MUL55:  LD      B, A            ; A = A * 55h (same slot in all four pages)
        ADD     A, A
        ADD     A, A
        OR      B
        LD      B, A
        ADD     A, A
        ADD     A, A
        ADD     A, A
        ADD     A, A
        OR      B
        RET

MIX:    LD      HL, (CFGRAM)    ; HL = CFGRAM, bits in C taken from CFGORG
        LD      DE, (CFGORG)
        LD      A, C
        CPL
        AND     H
        LD      B, A
        LD      A, D
        AND     C
        OR      B
        LD      H, A
        LD      A, C
        CPL
        AND     L
        LD      B, A
        LD      A, E
        AND     C
        OR      B
        LD      L, A
        RET

; Program ended (BDOS), slots as at the start
AFTER:  EI
        LD      HL, MSGEND
        CALL    PRINT
WREL:   CALL    SPACE
        JR      Z, WREL
WPRS:   CALL    SPACE
        JR      NZ, WPRS
        JP      RUN

SPACE:  LD      A, 8            ; Z = SPACE pressed
        CALL    SNSMAT
        AND     1
        RET

PRINT:  LD      A, (HL)
        OR      A
        RET     Z
        CALL    CHPUT
        INC     HL
        JR      PRINT

MSGEND: DB      13, 10, "SPACE: run again", 0

; Resident part, runs at ENV
ENVSRC:
        .PHASE  ENV

LOADRUN:
        LD      HL, (CFGLOAD)
        CALL    SETCFG
        LD      HL, 0           ; page 0 vectors
        LD      DE, 1
        LD      BC, 0FFh
        LD      (HL), L
        LDIR
        LD      A, 0C3h
        LD      (0000h), A
        LD      (0005h), A
        LD      (RDSLT), A
        LD      (001Ch), A
        LD      (KEYINT), A
        LD      HL, ENDPRG
        LD      (0001h), HL
        LD      (0006h), HL
        LD      HL, ERDSLT
        LD      (RDSLT + 1), HL
        LD      HL, ECALSLT
        LD      (001Dh), HL
        LD      HL, EKEYINT
        LD      (KEYINT + 1), HL
        LD      HL, COMIMG
        LD      DE, TPA
        LD      BC, COMLEN
        LDIR
        LD      HL, (CFGRAM)
        CALL    SETCFG
        LD      HL, TPA + COMLEN
        LD      DE, TPA + COMLEN + 1
        LD      BC, CLREND - TPA - COMLEN - 1
        LD      (HL), 0
        LDIR
        LD      HL, ENDPRG
        PUSH    HL
        EI
        JP      TPA

SETCFG: LD      A, H            ; keeps BC, DE, HL
        OUT     (0A8h), A
        LD      A, (EXPD)
        OR      A
        RET     Z
        LD      A, L
        LD      (0FFFFh), A
        RET

P0BIOS: PUSH    HL
        LD      HL, (CFGP0B)
        CALL    SETCFG
        POP     HL
        RET

P0RAM:  PUSH    HL
        LD      HL, (CFGRAM)
        CALL    SETCFG
        POP     HL
        RET

; CALSLT for the main BIOS only (IY ignored); returns with DI
ECALSLT:
        DI
        PUSH    AF
        CALL    P0BIOS
        POP     AF
        CALL    CALLIX
        DI
        PUSH    AF
        CALL    P0RAM
        POP     AF
        RET
CALLIX: JP      (IX)

; RDSLT through the BIOS; returns with DI
ERDSLT: DI
        PUSH    AF
        CALL    P0BIOS
        POP     AF
        CALL    RDSLT
        PUSH    AF
        CALL    P0RAM
        POP     AF
        RET

; Interrupt while vdpcmd has not hooked 0039h: the BIOS handler
EKEYINT:
        PUSH    AF
        PUSH    HL
        CALL    P0BIOS
        CALL    KEYINT
        DI
        CALL    P0RAM
        POP     HL
        POP     AF
        EI
        RET

ENDPRG: DI
        LD      SP, STACK
        LD      HL, (CFGORG)
        CALL    SETCFG
        JP      AFTER

CFGORG: DW      0
CFGRAM: DW      0
CFGLOAD:
        DW      0
CFGP0B: DW      0
EXPD:   DB      0
ENVTOP:
        .DEPHASE

ENVLEN  EQU     ENVTOP - ENV

COMIMG: INCBIN  "upstream/vdpcmd.com"
COMEND:
COMLEN  EQU     COMEND - COMIMG

        DS      8000h - $, 0FFh
