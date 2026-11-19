; PCMTEST for MSX turbo R - PCM played the way Criterion plays it
;
; Copyright (c) 2026 Molekula
; SPDX-License-Identifier: GPL-3.0-or-later
;
; 32 kB cartridge ROM at 4000h-BFFFh. Plays 8-bit unsigned samples on the turbo R PCM (A4h,
; A5h = 03h) with the player of the game Criterion: it reads the S1990 system timer (E7h, E6h;
; 3.911 us per tick) and outputs one sample every 32 ticks (7990 Hz). A sample is output when
; the player runs at or after its due time; when it comes 32 or more ticks late, the missed
; samples are skipped (2048 ticks or more: no skip, the due time restarts).
; The sound quality therefore depends only on how often the player is called. The ROM calls it
; in a tight loop and, optionally, does the work that keeps the game away from it: blocks of 256
; bytes written to the VRAM with OTIR once per frame (16.7 ms), as the game does at 4444h.
;
; Keys: 1-9 play a sound (the sounds chosen in build.sh, sounds.inc)
;       L   VDP load per frame: 0, 1, 2, 4 blocks of 256 bytes
;       C   chunked: the player is also called after every 16 bytes of a block (game: 54D8h)
;       I   interrupts on / off while playing
;       Z R D  CPU: Z80, R800 ROM, R800 DRAM (BIOS CHGCPU)
; After a sound: samples played, skipped, restarts, latest call (ticks after the due time) and
; player calls (a speed measure of the CPU).
;
; Build: build.sh (pasmo). The sound data are not part of the repository (README).

CHGET   EQU     009Fh
CHPUT   EQU     00A2h
INITXT  EQU     006Ch
RSLREG  EQU     0138h
ENASLT  EQU     0024h
CHGCPU  EQU     0180h
GETCPU  EQU     0183h
MSXVER  EQU     002Dh
LINL40  EQU     0F3AEh
CLIKSW  EQU     0F3DBh
EXPTBL  EQU     0FCC1h

TICKS   EQU     32              ; ticks per sample
FRAME   EQU     4266            ; ticks per 60 Hz frame (16.68 ms)

; RAM (page 3)
DUE     EQU     0E000h          ; timer value of the next sample
PTR     EQU     0E002h
REMAIN  EQU     0E004h
PLAYED  EQU     0E006h
SKIPPED EQU     0E008h
RESYNC  EQU     0E00Ah
MAXLATE EQU     0E00Ch
POLLS   EQU     0E00Eh          ; 32 bit
NEXTF   EQU     0E012h
DONE    EQU     0E014h
LOAD    EQU     0E015h          ; blocks per frame
CHUNK   EQU     0E016h
INTS    EQU     0E017h
NUM     EQU     0E018h          ; 32 bit for PRDEC

        ORG     4000h
        DB      "AB"
        DW      INIT
        DW      0, 0, 0
        DS      6, 0

INIT:   DI
        LD      SP, 0F380h
        ; page 2 = slot of page 1 (32 kB ROM)
        CALL    RSLREG
        RRCA
        RRCA
        AND     3
        LD      C, A
        LD      B, 0
        LD      HL, EXPTBL
        ADD     HL, BC
        LD      A, (HL)
        AND     80h
        OR      C
        LD      C, A
        INC     HL
        INC     HL
        INC     HL
        INC     HL
        LD      A, (HL)
        AND     0Ch
        OR      C
        LD      H, 80h
        CALL    ENASLT
        LD      A, 40
        LD      (LINL40), A
        XOR     A
        LD      (CLIKSW), A
        LD      (LOAD), A
        LD      (CHUNK), A
        LD      (INTS), A
        CALL    INITXT
        EI
        LD      HL, S_TITLE
        CALL    PRINT
        LD      HL, S_LIST
        CALL    PRINT
        LD      A, (MSXVER)
        CP      3
        JR      NC, TR
        LD      HL, S_NOTR
        CALL    PRINT
STOP:   JR      STOP
TR:     LD      A, 82h          ; R800 DRAM, as the game
        CALL    CHGCPU
        EI

MENU:   CALL    STATUS
KEY:    CALL    CHGET
        AND     0DFh            ; upper case (digits change, compared below)
        CP      'L'
        JP      Z, K_LOAD
        CP      'C'
        JP      Z, K_CHUNK
        CP      'I'
        JP      Z, K_INTS
        CP      'Z'
        JP      Z, K_Z80
        CP      'R'
        JP      Z, K_ROM
        CP      'D'
        JP      Z, K_DRAM
        SUB     11h             ; '1' AND DFh
        JP      C, KEY
        CP      NSND            ; sounds.inc (build.sh)
        JP      NC, KEY
        LD      C, A
        ADD     A, A
        ADD     A, A
        LD      E, A
        LD      D, 0
        LD      IX, SNDTAB
        ADD     IX, DE
        LD      L, (IX + 0)
        LD      H, (IX + 1)
        LD      E, (IX + 2)
        LD      D, (IX + 3)
        LD      A, C
        ADD     A, 31h          ; '1'
        JP      PLAYKEY

K_LOAD: LD      A, (LOAD)       ; 0 1 2 4
        ADD     A, A
        JR      NZ, KL1
        INC     A
KL1:    CP      8
        JR      C, KL2
        XOR     A
KL2:    LD      (LOAD), A
        JP      MENU
K_CHUNK:
        LD      HL, CHUNK
        LD      A, (HL)
        XOR     1
        LD      (HL), A
        JP      MENU
K_INTS: LD      HL, INTS
        LD      A, (HL)
        XOR     1
        LD      (HL), A
        JP      MENU
K_Z80:  LD      A, 80h
        JP      KCPU
K_ROM:  LD      A, 81h
        JP      KCPU
K_DRAM: LD      A, 82h
KCPU:   CALL    CHGCPU
        EI
        JP      MENU
PLAYKEY:
        PUSH    HL
        PUSH    DE
        PUSH    AF
        LD      HL, S_PLAY
        CALL    PRINT
        POP     AF
        CALL    CHPUT
        LD      HL, S_CRLF
        CALL    PRINT
        POP     DE
        POP     HL
        CALL    PLAY
        CALL    RESULT
        JP      KEY

; --- one sound: HL data, DE length ---
PLAY:   LD      (PTR), HL
        LD      (REMAIN), DE
        LD      HL, 0
        LD      (PLAYED), HL
        LD      (SKIPPED), HL
        LD      (RESYNC), HL
        LD      (MAXLATE), HL
        LD      (POLLS), HL
        LD      (POLLS + 2), HL
        XOR     A
        LD      (DONE), A
        DI
        LD      A, 03h          ; PCM on, as the game
        OUT     (0A5h), A
        LD      A, (INTS)
        OR      A
        JR      Z, PL1
        EI
PL1:    CALL    NOW
        LD      (DUE), HL
        LD      DE, FRAME
        ADD     HL, DE
        LD      (NEXTF), HL
PLOOP:  CALL    POLL
        LD      HL, POLLS
        INC     (HL)
        JR      NZ, PL2
        INC     HL
        INC     (HL)
        JR      NZ, PL2
        INC     HL
        INC     (HL)
        JR      NZ, PL2
        INC     HL
        INC     (HL)
PL2:    LD      A, (DONE)
        OR      A
        JR      NZ, PLEND
        LD      A, (LOAD)
        OR      A
        JR      Z, PLOOP
        CALL    NOW
        LD      DE, (NEXTF)
        OR      A
        SBC     HL, DE
        JP      M, PLOOP
        LD      HL, FRAME
        ADD     HL, DE
        LD      (NEXTF), HL
        CALL    WORK
        JR      PLOOP
PLEND:  LD      A, 80h
        OUT     (0A4h), A
        EI
        RET

NOW:    IN      A, (0E7h)
        LD      H, A
        IN      A, (0E6h)
        LD      L, A
        RET

; --- the player (Criterion 4F18h / 4F28h / 4F36h) ---
POLL:   IN      A, (0E7h)
        LD      H, A
        IN      A, (0E6h)
        LD      L, A
        LD      DE, (DUE)
        OR      A
        SBC     HL, DE
        RET     M               ; not due yet
        LD      BC, 0
        LD      A, H
        OR      A
        JR      NZ, P_LATE
        LD      A, L
        CP      TICKS
        JR      NC, P_LATE
        LD      HL, TICKS       ; in time
        ADD     HL, DE
        LD      (DUE), HL
        JR      P_OUT
P_LATE: LD      DE, (MAXLATE)
        PUSH    HL
        OR      A
        SBC     HL, DE
        POP     HL
        JR      C, P_L1
        LD      (MAXLATE), HL
P_L1:   LD      DE, (DUE)
        LD      A, H
        CP      08h
        JR      C, P_SKIP
        ADD     HL, DE          ; 2048 ticks or more: restart from now
        LD      (DUE), HL
        LD      HL, (RESYNC)
        INC     HL
        LD      (RESYNC), HL
        JR      P_OUT
P_SKIP: LD      A, L
        AND     0E0h
        LD      L, A
        PUSH    HL
        ADD     HL, DE
        LD      DE, TICKS
        ADD     HL, DE
        LD      (DUE), HL
        POP     HL
        LD      B, 5
P_SH:   SRL     H
        RR      L
        DJNZ    P_SH
        LD      B, H
        LD      C, L
        LD      HL, (SKIPPED)
        ADD     HL, BC
        LD      (SKIPPED), HL
P_OUT:  LD      HL, (REMAIN)
        OR      A
        SBC     HL, BC
        JR      C, P_END
        JR      Z, P_END
        DEC     HL
        LD      (REMAIN), HL
        LD      HL, (PTR)
        ADD     HL, BC
        LD      A, (HL)
        OUT     (0A4h), A
        INC     HL
        LD      (PTR), HL
        LD      HL, (PLAYED)
        INC     HL
        LD      (PLAYED), HL
        RET
P_END:  LD      A, 1
        LD      (DONE), A
        RET

; --- VDP load: LOAD blocks of 256 bytes to VRAM 4000h (not shown in SCREEN 0) ---
WORK:   DI
        LD      A, (LOAD)
        LD      B, A
W_BLK:  PUSH    BC
        LD      A, 1            ; R#14 = 1, address 0: VRAM 4000h
        OUT     (99h), A
        LD      A, 8Eh
        OUT     (99h), A
        XOR     A
        OUT     (99h), A
        LD      A, 40h
        OUT     (99h), A
        LD      HL, 4000h       ; any bytes
        LD      C, 98h
        LD      A, (CHUNK)
        OR      A
        JR      NZ, W_CH
        LD      B, 0
        OTIR
        JR      W_NEXT
W_CH:   LD      E, 16
W_C1:   LD      B, 16
        OTIR
        PUSH    HL
        PUSH    DE
        CALL    POLL
        POP     DE
        POP     HL
        LD      C, 98h
        DEC     E
        JR      NZ, W_C1
W_NEXT: POP     BC
        DJNZ    W_BLK
        XOR     A               ; R#14 = 0
        OUT     (99h), A
        LD      A, 8Eh
        OUT     (99h), A
        LD      A, (INTS)
        OR      A
        RET     Z
        EI
        RET

; --- texts ---
STATUS: LD      HL, S_CPU
        CALL    PRINT
        CALL    GETCPU
        LD      HL, S_Z80
        OR      A
        JR      Z, ST1
        LD      HL, S_R800R
        DEC     A
        JR      Z, ST1
        LD      HL, S_R800D
ST1:    CALL    PRINT
        LD      HL, S_LOAD
        CALL    PRINT
        LD      A, (LOAD)
        ADD     A, '0'
        CALL    CHPUT
        LD      HL, S_CHUNK
        CALL    PRINT
        LD      A, (CHUNK)
        CALL    ONOFF
        LD      HL, S_INTS
        CALL    PRINT
        LD      A, (INTS)
        CALL    ONOFF
        LD      HL, S_CRLF
        JP      PRINT

ONOFF:  LD      HL, S_OFF
        OR      A
        JR      Z, PRINT
        LD      HL, S_ON
PRINT:  LD      A, (HL)
        OR      A
        RET     Z
        CALL    CHPUT
        INC     HL
        JR      PRINT

RESULT: LD      HL, S_R1
        CALL    PRINT
        LD      HL, (PLAYED)
        CALL    PRDEC16
        LD      HL, S_R2
        CALL    PRINT
        LD      HL, (SKIPPED)
        CALL    PRDEC16
        LD      HL, S_R3
        CALL    PRINT
        LD      HL, (RESYNC)
        CALL    PRDEC16
        LD      HL, S_R4
        CALL    PRINT
        LD      HL, (MAXLATE)
        CALL    PRDEC16
        LD      HL, S_R5
        CALL    PRINT
        LD      HL, (POLLS)
        LD      DE, (POLLS + 2)
        CALL    PRDEC32
        LD      HL, S_CRLF
        JP      PRINT

PRDEC16:
        LD      DE, 0
; DEHL in decimal, no leading zeros
PRDEC32:
        LD      IY, POW10
        LD      B, 10
        LD      C, 0            ; 1 = a digit was printed
PD1:    LD      A, 2Fh          ; '0' - 1 (pasmo: no character arithmetic)
PD2:    INC     A
        PUSH    AF
        LD      A, L
        SUB     (IY + 0)
        LD      L, A
        LD      A, H
        SBC     A, (IY + 1)
        LD      H, A
        LD      A, E
        SBC     A, (IY + 2)
        LD      E, A
        LD      A, D
        SBC     A, (IY + 3)
        LD      D, A
        JR      C, PD3
        POP     AF
        JR      PD2
PD3:    LD      A, L
        ADD     A, (IY + 0)
        LD      L, A
        LD      A, H
        ADC     A, (IY + 1)
        LD      H, A
        LD      A, E
        ADC     A, (IY + 2)
        LD      E, A
        LD      A, D
        ADC     A, (IY + 3)
        LD      D, A
        POP     AF
        CP      '0'
        JR      NZ, PD4
        BIT     0, C
        JR      NZ, PD4
        LD      A, B
        DEC     A
        JR      NZ, PD5         ; leading zero, not the last digit
        LD      A, '0'
PD4:    PUSH    IY
        PUSH    HL
        PUSH    DE
        PUSH    BC
        CALL    CHPUT
        POP     BC
        POP     DE
        POP     HL
        POP     IY
        LD      C, 1
PD5:    INC     IY
        INC     IY
        INC     IY
        INC     IY
        DJNZ    PD1
        RET

POW10:  DW      0CA00h, 3B9Ah   ; 1000000000
        DW      0E100h, 05F5h   ; 100000000
        DW      9680h, 0098h    ; 10000000
        DW      4240h, 000Fh    ; 1000000
        DW      86A0h, 0001h    ; 100000
        DW      10000, 0
        DW      1000, 0
        DW      100, 0
        DW      10, 0
        DW      1, 0

S_TITLE:DB      "PCMTEST - turbo R PCM, Criterion player", 13, 10
        DB      "7990 Hz: 1 sample per 32 ticks of E6h", 13, 10
        DB      "1-9 play  L load  C chunked  I ints", 13, 10
        DB      "Z Z80  R R800 ROM  D R800 DRAM", 13, 10, 0
S_NOTR: DB      "Needs a turbo R (PCM, S1990 timer)", 13, 10, 0
S_CPU:  DB      "CPU ", 0
S_Z80:  DB      "Z80", 0
S_R800R:DB      "R800 ROM", 0
S_R800D:DB      "R800 DRAM", 0
S_LOAD: DB      " load ", 0
S_CHUNK:DB      " chunk ", 0
S_INTS: DB      " int ", 0
S_ON:   DB      "on", 0
S_OFF:  DB      "off", 0
S_PLAY: DB      "sound ", 0
S_R1:   DB      "played ", 0
S_R2:   DB      " skipped ", 0
S_R3:   DB      " restart ", 0
S_R4:   DB      13, 10, " late max ", 0
S_R5:   DB      " calls ", 0
S_CRLF: DB      13, 10, 0

        INCLUDE "sounds.inc"           ; NSND, SNDTAB, S_LIST and the samples (build.sh)

        DS      0C000h - $, 0FFh        ; fails when the data do not fit into 32 kB
