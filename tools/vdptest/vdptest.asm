; VDPTEST for MSX - timing and flag tests of the VDP (TMS9918A/28A/29A, V9938, V9958)
;
; Copyright (c) 2026 Molekula
; SPDX-License-Identifier: GPL-3.0-or-later
;
; 16 kB cartridge ROM at 4000h. Runs on the FPGA core and on openMSX; the results are
; compared between the two (README.md). The VDP type is detected in software, tests
; that need a V9938/V9958 are skipped on a TMS99xx.
;
; Build: build.sh (pasmo). --equ AUTO=1 builds a variant that pages through all tests
; by itself (simulation, rtl/tb/machine_boot_tb).
;
; Keys: SPACE = next page, RETURN = previous page. Every page measures when entered.
;
; Measurements run with interrupts off, polling the status register with LOOP in RAM:
;   IN A,(99h) / AND m / JR cc,end / INC HL / LD A,H / INC A / JP NZ,loop
; = 56 T per iteration on an MSX (one M1 wait state per opcode byte fetch).
; 65280 iterations (about 1 s) is a timeout, shown as "-----".

        IFNDEF AUTO
AUTO    EQU     0
        ENDIF
        IFNDEF STARTPG
STARTPG EQU     0               ; first page (debugging)
        ENDIF

VDPD    EQU     98h
VDPC    EQU     99h
VDPP    EQU     9Ah
VDPI    EQU     9Bh
PPIB    EQU     0A9h            ; keyboard columns
PPIC    EQU     0AAh            ; keyboard row (low nibble)

CGTABL  EQU     0004h           ; BIOS: font address
MSXVER  EQU     002Dh           ; BIOS: 0 MSX1, 1 MSX2, 2 MSX2+, 3 turbo R
CHGCPU  EQU     0180h           ; BIOS (turbo R): change CPU
RG9SAV  EQU     0FFE8h          ; BIOS copy of R#9 (MSX2 and later)

; RAM, E000h-EFFFh (present on every MSX)
VTYPE   EQU     0E000h          ; 0 TMS99xx, 1 V9938, 2 V9958
VID     EQU     0E001h          ; V99x8 ID from S#1
MVER    EQU     0E002h
PAGE    EQU     0E003h
RG0     EQU     0E004h
RG1     EQU     0E005h
PALB    EQU     0E006h          ; R#9 PAL bit (02h) of the BIOS
DIRN    EQU     0E007h          ; last paging direction (1 / FFh)
CUR     EQU     0E008h          ; text cursor in SHADOW
ISRV    EQU     0E00Ah          ; ISR scratch
ACC     EQU     0E00Ch          ; OR of status reads
RESULT     EQU     0E010h          ; results, words
IM2TAB  EQU     0E100h          ; 257 bytes of 0E6h (E100h-E200h)
SHADOW  EQU     0E300h          ; 32 x 24 text screen
ISRJP   EQU     0E6E6h          ; JP to the ISR (IM2 vector E6E6h)
LOOP    EQU     0E700h          ; counting loop
STACK   EQU     0EF00h

NPAGES  EQU     8

        ORG     4000h
        DB      "AB"
        DW      START
        DW      0, 0, 0
        DS      6, 0

; ------------------------------------------------------------------------- start
START:  DI
        LD      SP, STACK
        LD      A, (MSXVER)
        LD      (MVER), A
        CP      3
        JR      NZ, NOTR
        XOR     A                       ; turbo R: Z80 mode, the loops count Z80 T
        CALL    CHGCPU
        DI
NOTR:   LD      A, (RG9SAV)
        AND     02h
        LD      (PALB), A
        CALL    DETECT
        LD      A, (VTYPE)              ; RG9SAV exists only on MSX2 and later
        OR      A
        JR      NZ, PALOK
        XOR     A
        LD      (PALB), A
PALOK:
        ; counting loop and IM2 table into RAM
        LD      HL, LOOPSRC
        LD      DE, LOOP
        LD      BC, LOOPEND - LOOPSRC
        LDIR
        LD      HL, IM2TAB
        LD      DE, IM2TAB + 1
        LD      BC, 256
        LD      (HL), 0E6h
        LDIR
        LD      A, 0C3h
        LD      (ISRJP), A
        LD      HL, ISRBAR
        LD      (ISRJP + 1), HL
        LD      A, IM2TAB / 256
        LD      I, A
        IM      2
        LD      A, STARTPG
        LD      (PAGE), A
        LD      A, 1
        LD      (DIRN), A

MAIN:   LD      A, (PAGE)               ; skip V99x8 pages on a TMS99xx
        LD      L, A
        LD      H, 0
        ADD     HL, HL
        ADD     HL, HL
        LD      DE, PAGES
        ADD     HL, DE
        LD      A, (VTYPE)
        OR      A
        JR      NZ, MAINRUN
        INC     HL
        INC     HL
        LD      A, (HL)
        DEC     HL
        DEC     HL
        OR      A
        JR      Z, MAINRUN
        JR      MAINNXT
MAINRUN:
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        CALL    JPHL
        CALL    GETKEY                  ; A = 1 next, FFh previous
        LD      (DIRN), A
        DI
        CALL    QUIET
MAINNXT:
        LD      A, (DIRN)
        LD      B, A
        LD      A, (PAGE)
        ADD     A, B
        CP      NPAGES
        JR      C, MAINSET
        CP      0FFh
        LD      A, 0
        JR      NZ, MAINSET
        LD      A, NPAGES - 1
MAINSET:
        LD      (PAGE), A
        JP      MAIN

JPHL:   JP      (HL)

; page table: routine, 1 = needs a V9938 / V9958
PAGES:  DW      PGINFO, 0
        DW      PGBARS, 0
        DW      PGVR, 1
        DW      PGLINE, 1
        DW      PGFH, 1
        DW      PGSPRT, 0
        DW      PGCOLL, 0
        DW      PGCMD, 1

; counting loop, copied to LOOP: the mask at LOOP+3, the condition at LOOP+4
LOOPSRC:
        IN      A, (VDPC)
        AND     0FFh
        JR      Z, LOOPSRC + 12
        INC     HL
        LD      A, H
        INC     A
        JP      NZ, LOOP
        RET
LOOPEND:

; count HL iterations until (status AND B) is non zero (C = 20h, JR NZ) or zero (C = 28h)
CNTNZ:  LD      C, 20h
        JR      CNT
CNTZ:   LD      C, 28h
CNT:    LD      A, B
        LD      (LOOP + 3), A
        LD      A, C
        LD      (LOOP + 4), A
        LD      HL, 0
        JP      LOOP

; ------------------------------------------------------------------------- VDP access
; A = value, E = register
WRREG:  OUT     (VDPC), A
        LD      A, E
        OR      80h
        OUT     (VDPC), A
        RET

; status register select (V99x8 only), A = number
SELST:  LD      E, 15
        JR      WRREG

; wait for F (S#0 bit 7); R#15 must be 0
WAITF:  IN      A, (VDPC)
        RLCA
        JR      NC, WAITF
        RET

; read S#0 until F, OR of all reads in ACC (catches C / 5S cleared by the polling)
ACCF:   LD      D, 0
ACCF1:  IN      A, (VDPC)
        LD      E, A
        OR      D
        LD      D, A
        BIT     7, E
        JR      Z, ACCF1
        LD      A, D
        LD      (ACC), A
        RET

; VRAM write address HL (64 kB; R#14 only on a V99x8)
SETWR:  LD      A, (VTYPE)
        OR      A
        JR      Z, SETWR1
        LD      A, H
        RLCA
        RLCA
        AND     03h
        LD      E, 14
        CALL    WRREG
SETWR1: LD      A, L
        OUT     (VDPC), A
        LD      A, H
        AND     3Fh
        OR      40h
        OUT     (VDPC), A
        RET

; fill VRAM: HL address, BC count, D value
FILVRM: CALL    SETWR
FILV1:  LD      A, D
        OUT     (VDPD), A
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, FILV1
        RET

; copy to VRAM: HL source, DE VRAM address, BC count
LDIRVM: PUSH    HL
        EX      DE, HL
        CALL    SETWR
        POP     HL
LDV1:   LD      A, (HL)
        OUT     (VDPD), A
        INC     HL
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, LDV1
        RET

; R#1 with the display on / off (keeps the other bits of RG1)
DISPON: LD      A, (RG1)
        OR      40h
        JR      SETR1
DISPOFF:
        LD      A, (RG1)
        AND     0BFh
SETR1:  LD      (RG1), A
        LD      E, 1
        JR      WRREG

; interrupts off in the VDP, status S#0, line interrupt line 0
QUIET:  LD      A, (RG1)
        AND     0DFh
        CALL    SETR1
        LD      A, (VTYPE)
        OR      A
        RET     Z
        LD      A, (RG0)
        AND     0EFh
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        XOR     A
        LD      E, 19
        CALL    WRREG
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        RET

; ------------------------------------------------------------------------- detection
; R#15 = 1: a V99x8 then returns S#1 (bit 7 FL = 0, ID in bits 5-1); a TMS99xx writes
; R#7 instead and keeps returning S#0, whose bit 7 (F) sets within a frame.
DETECT: XOR     A
        LD      (VTYPE), A
        LD      (VID), A
        IN      A, (VDPC)
        LD      A, 1
        CALL    SELST
        LD      BC, 4000                ; about 3 frames
DET1:   IN      A, (VDPC)
        RLCA
        JR      C, DETTMS
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, DET1
        IN      A, (VDPC)
        RRCA
        AND     1Fh
        LD      (VID), A
        LD      B, 1
        OR      A
        JR      Z, DET2
        INC     B                       ; ID 2 (and others): V9958
DET2:   LD      A, B
        LD      (VTYPE), A
        XOR     A
        CALL    SELST
DETTMS: RET

; ------------------------------------------------------------------------- text screen
; Graphic 1, font from the BIOS, white on black, border dark blue
TEXTINIT:
        LD      A, 80h
        LD      (RG1), A
        LD      E, 1
        CALL    WRREG
        XOR     A
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        LD      HL, G1REGS
        LD      E, 2
TI1:    LD      A, (HL)
        CALL    WRREG
        INC     HL
        INC     E
        LD      A, E
        CP      8
        JR      NZ, TI1
        LD      A, (VTYPE)
        OR      A
        JR      Z, TI2
        LD      HL, V9REGS              ; register, value pairs, 0FFh end
TI3:    LD      E, (HL)
        INC     HL
        LD      A, E
        CP      0FFh
        JR      Z, TI4
        LD      A, (HL)
        INC     HL
        CALL    WRREG
        JR      TI3
TI4:    LD      A, (PALB)
        LD      E, 9
        CALL    WRREG
TI2:    LD      HL, 0                   ; clear 16 kB
        LD      BC, 4000h
        LD      D, 0
        CALL    FILVRM
        LD      HL, (CGTABL)            ; font
        LD      DE, 0
        LD      BC, 2048
        CALL    LDIRVM
        LD      HL, 0400h               ; char 80h: solid block
        LD      BC, 8
        LD      D, 0FFh
        CALL    FILVRM
        LD      HL, 2000h               ; colours: white on black
        LD      BC, 32
        LD      D, 0F1h
        CALL    FILVRM
        LD      HL, 2010h               ; chars 80h-87h: grey
        LD      BC, 1
        LD      D, 0EEh
        CALL    FILVRM
        LD      HL, 1B00h               ; no sprites
        LD      BC, 1
        LD      D, 0D0h
        CALL    FILVRM
        LD      HL, 3800h               ; sprite pattern 0: solid
        LD      BC, 8
        LD      D, 0FFh
        CALL    FILVRM
        CALL    CLS
        RET

G1REGS: DB      06h, 80h, 00h, 36h, 07h, 0F4h       ; R#2-R#7
V9REGS: DB      8, 08h, 11, 0, 14, 0, 15, 0, 18, 0, 19, 0, 23, 0, 0FFh

CLS:    LD      HL, SHADOW
        LD      DE, SHADOW + 1
        LD      BC, 767
        LD      (HL), 20h
        LDIR
        LD      HL, SHADOW
        LD      (CUR), HL
        RET

; cursor: B = column, C = row
LOCATE: LD      L, C
        LD      H, 0
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        LD      E, B
        LD      D, 0
        ADD     HL, DE
        LD      DE, SHADOW
        ADD     HL, DE
        LD      (CUR), HL
        RET

; print the string after the CALL (0 terminated)
PRINTI: EX      (SP), HL
        CALL    PRINT
        EX      (SP), HL
        RET

; print HL (0 terminated), HL ends after the 0
PRINT:  LD      DE, (CUR)
PR1:    LD      A, (HL)
        INC     HL
        OR      A
        JR      Z, PR2
        LD      (DE), A
        INC     DE
        JR      PR1
PR2:    LD      (CUR), DE
        RET

PRCHR:  LD      DE, (CUR)
        LD      (DE), A
        INC     DE
        LD      (CUR), DE
        RET

; HL as 5 digits, right aligned; timeout (FFxxh from LOOP) as -----
PRNUM:  LD      A, H
        CP      0FFh
        JR      NZ, PN0
        CALL    PRINTI
        DB      "-----", 0
        RET
PN0:    LD      B, 0                    ; B = 1 once a digit was printed
        LD      DE, 10000
        CALL    PNDIG
        LD      DE, 1000
        CALL    PNDIG
        LD      DE, 100
        CALL    PNDIG
        LD      DE, 10
        CALL    PNDIG
        LD      A, L
        ADD     A, '0'
        JR      PRCHR
PNDIG:  LD      C, '0'
PND1:   OR      A
        SBC     HL, DE
        JR      C, PND2
        INC     C
        JR      PND1
PND2:   ADD     HL, DE
        LD      A, C
        CP      '0'
        JR      NZ, PND3
        LD      A, B
        OR      A
        LD      A, ' '
        JR      Z, PND4
        LD      A, '0'
PND3:   LD      B, 1
PND4:   PUSH    BC
        PUSH    HL
        CALL    PRCHR
        POP     HL
        POP     BC
        RET

; bit 0/1 of A as '0'/'1'
PRBIT:  AND     1
        ADD     A, '0'
        JR      PRCHR

; title line and the key help line
HEADER: PUSH    HL
        CALL    CLS
        CALL    PRINTI
        DB      "VDPTEST ", 0
        LD      A, (VTYPE)
        LD      HL, TXTTMS
        OR      A
        JR      Z, HD1
        LD      HL, TXT38
        DEC     A
        JR      Z, HD1
        LD      HL, TXT58
HD1:    CALL    PRINT
        LD      A, (PALB)
        OR      A
        LD      HL, TXTPAL
        JR      NZ, HD2
        LD      HL, TXTNTSC
        LD      A, (VTYPE)
        OR      A
        JR      NZ, HD2
        LD      HL, TXTEMPTY            ; TMS: PAL / NTSC from the frame length
HD2:    CALL    PRINT
        LD      BC, 0 * 256 + 23
        CALL    LOCATE
        CALL    PRINTI
        DB      "SPACE NEXT  RETURN PREV   P", 0
        LD      A, (PAGE)
        INC     A
        ADD     A, '0'
        CALL    PRCHR
        LD      BC, 0 * 256 + 2
        CALL    LOCATE
        POP     HL
        CALL    PRINT
        JP      NL

TXTTMS: DB      "TMS99XX", 0
TXT38:  DB      "V9938", 0
TXT58:  DB      "V9958", 0
TXTPAL: DB      " PAL", 0
TXTNTSC:
        DB      " NTSC", 0
TXTEMPTY:
        DB      0

; next text line (column 0)
NL:     LD      HL, (CUR)
        LD      DE, SHADOW
        OR      A
        SBC     HL, DE
        LD      A, L
        AND     0E0h
        LD      L, A
        LD      DE, SHADOW + 32
        ADD     HL, DE
        LD      (CUR), HL
        RET

; text to the screen; the display is off during the copy (no access slot waits)
SHOW:   CALL    DISPOFF
        LD      HL, SHADOW
        LD      DE, 1800h
        LD      BC, 768
        CALL    LDIRVM
        JP      DISPON

; print the words RESULT .. (B words) as numbers, 6 columns each, 5 per line
PRRES:  LD      HL, RESULT
PRR1:   PUSH    BC
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        PUSH    HL
        EX      DE, HL
        LD      A, ' '
        CALL    PRCHR
        CALL    PRNUM
        POP     HL
        POP     BC
        DJNZ    PRR1
        RET

; store HL as result C (word index)
STORE:  PUSH    HL
        LD      L, C
        LD      H, 0
        ADD     HL, HL
        LD      DE, RESULT
        ADD     HL, DE
        POP     DE
        LD      (HL), E
        INC     HL
        LD      (HL), D
        EX      DE, HL
        RET

; ------------------------------------------------------------------------- keys
; A: bit 0 SPACE (row 8 bit 0), bit 1 RETURN (row 7 bit 7)
READKEYS:
        IN      A, (PPIC)
        AND     0F0h
        OR      8
        OUT     (PPIC), A
        IN      A, (PPIB)
        CPL
        AND     1
        LD      B, A
        IN      A, (PPIC)
        AND     0F0h
        OR      7
        OUT     (PPIC), A
        IN      A, (PPIB)
        CPL
        AND     80h
        JR      Z, RK1
        SET     1, B
RK1:    LD      A, B
        RET

; wait for a key, A = 1 (SPACE) or FFh (RETURN)
GETKEY:
        IF      AUTO
        LD      B, 1                    ; AUTO: about 0.55 s, then next page
GK0:    LD      DE, 0
GK00:   DEC     DE
        LD      A, D
        OR      E
        JR      NZ, GK00
        DJNZ    GK0
        LD      A, 1
        RET
        ELSE
GK1:    CALL    READKEYS                ; release
        OR      A
        JR      NZ, GK1
        CALL    DEBOUNCE
GK2:    CALL    READKEYS
        OR      A
        JR      Z, GK2
        PUSH    AF
        CALL    DEBOUNCE
        POP     AF
        RRCA
        LD      A, 1
        RET     C
        LD      A, 0FFh
        RET
        ENDIF

DEBOUNCE:
        LD      DE, 2000
DB1:    DEC     DE
        LD      A, D
        OR      E
        JR      NZ, DB1
        RET

; delay of about DE * 30 T
DELAY:  DEC     DE
        LD      A, D
        OR      E
        JR      NZ, DELAY
        RET

; ------------------------------------------------------------------------- page 1: info
PGINFO: CALL    TEXTINIT
        LD      HL, T_INFO
        CALL    HEADER
        CALL    NL
        CALL    PRINTI
        DB      "MSX VERSION BYTE (2DH):", 0
        LD      A, (MVER)
        ADD     A, '0'
        CALL    PRCHR
        CALL    NL
        CALL    PRINTI
        DB      "V99X8 ID (S#1 BITS 5-1):", 0
        LD      A, (VID)
        ADD     A, '0'
        CALL    PRCHR
        CALL    NL
        CALL    NL
        CALL    PRINTI
        DB      "FRAME, F TO F (56 T/ITER):", 0
        CALL    NL
        CALL    SHOW
        IN      A, (VDPC)
        CALL    WAITF
        LD      C, 0
PI1:    PUSH    BC
        LD      B, 80h
        CALL    CNTNZ
        POP     BC
        CALL    STORE
        INC     C
        LD      A, C
        CP      5
        JR      NZ, PI1
        LD      B, 5
        CALL    PRRES
        CALL    NL
        CALL    NL
        CALL    PRINTI
        DB      "MODEL NTSC 262 LINES: 1066", 0
        CALL    NL
        CALL    PRINTI
        DB      "MODEL PAL  313 LINES: 1274", 0
        CALL    NL
        CALL    PRINTI
        DB      "(228 T/LINE; FEW ITER. LOST", 0
        CALL    NL
        CALL    PRINTI
        DB      " BETWEEN THE MEASUREMENTS)", 0
        JP      SHOW

T_INFO: DB      "INFO", 0

; ------------------------------------------------------------------------- page 2: bars
; VBLANK interrupt: white border bar; V99x8 line interrupt (R#19 = 96): yellow bar.
; The bar starts at the interrupt plus the ISR latency (about 0.3 line).
PGBARS: CALL    TEXTINIT
        LD      A, 0FDh                 ; border magenta
        LD      E, 7
        CALL    WRREG
        LD      HL, T_BARS
        CALL    HEADER
        CALL    PRINTI
        DB      "WHITE: VBLANK IRQ", 0
        CALL    NL
        LD      A, (VTYPE)
        OR      A
        JR      Z, PB1
        CALL    PRINTI
        DB      "YELLOW: LINE IRQ R#19=96", 0
PB1:    LD      HL, SHADOW + 4 * 32     ; picture rows 4-22: grey block
        LD      DE, SHADOW + 4 * 32 + 1
        LD      BC, 19 * 32 - 1
        LD      (HL), 80h
        LDIR
        CALL    SHOW
        LD      A, (VTYPE)
        OR      A
        JR      Z, PB2
        LD      A, 96
        LD      E, 19
        CALL    WRREG
        LD      A, 10h                  ; IE1
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        LD      A, 1
        CALL    SELST
        IN      A, (VDPC)
        XOR     A
        CALL    SELST
PB2:    IN      A, (VDPC)
        LD      A, (RG1)
        OR      20h                     ; IE0
        CALL    SETR1
        EI
        RET

ISRBAR: PUSH    AF
        PUSH    BC
        LD      A, (VTYPE)
        OR      A
        JR      Z, IBV
        LD      A, 1
        OUT     (VDPC), A
        LD      A, 8Fh
        OUT     (VDPC), A
        IN      A, (VDPC)               ; S#1, clears FH
        LD      C, A
        XOR     A
        OUT     (VDPC), A
        LD      A, 8Fh
        OUT     (VDPC), A
        BIT     0, C
        JR      Z, IBV
        LD      A, 0FBh                 ; yellow
        JR      IBBAR
IBV:    IN      A, (VDPC)               ; S#0, clears F
        RLCA
        JR      NC, IBEND
        LD      A, 0FFh                 ; white
IBBAR:  OUT     (VDPC), A
        LD      A, 87h
        OUT     (VDPC), A
        LD      B, 48                   ; about 3 lines
IBD:    DJNZ    IBD
        LD      A, 0FDh
        OUT     (VDPC), A
        LD      A, 87h
        OUT     (VDPC), A
IBEND:  POP     BC
        POP     AF
        EI
        RETI

T_BARS: DB      "IRQ BARS (VISUAL)", 0

; ------------------------------------------------------------------------- page 3: VR
; From F: iterations until VR = 0 (display starts one line later), then until VR = 1
; (end of the display), and F read right after VR = 1.
PGVR:   CALL    TEXTINIT
        LD      HL, T_VR
        CALL    HEADER
        CALL    PRINTI
        DB      "F TO VR=0, VR=0 TIME, F AT VR=1", 0
        CALL    NL
        CALL    SHOW
        LD      C, 0
PV1:    PUSH    BC
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        CALL    WAITF
        LD      A, 2
        CALL    SELST
        LD      B, 40h
        CALL    CNTZ
        POP     BC
        PUSH    BC
        CALL    STORE
        LD      B, 40h
        CALL    CNTNZ
        POP     BC
        PUSH    BC
        INC     C
        CALL    STORE
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        RLCA
        AND     1
        LD      L, A
        LD      H, 0
        POP     BC
        PUSH    BC
        INC     C
        INC     C
        CALL    STORE
        POP     BC
        LD      A, C
        ADD     A, 3
        LD      C, A
        CP      12
        JR      NZ, PV1
        LD      HL, RESULT                 ; 4 rows of 3
        LD      B, 4
PV2:    PUSH    BC
        PUSH    HL
        LD      B, 3
        CALL    PRRESHL
        CALL    NL
        POP     HL
        LD      DE, 6
        ADD     HL, DE
        POP     BC
        DJNZ    PV2
        CALL    NL
        CALL    PRINTI
        DB      "MODEL NTSC 192: 281 786 1", 0
        CALL    NL
        CALL    PRINTI
        DB      "      PAL  192: 489 786 1", 0
        CALL    NL
        CALL    PRINTI
        DB      "(VR=0 FROM THE LINE BEFORE THE", 0
        CALL    NL
        CALL    PRINTI
        DB      " DISPLAY TO ITS END, F AT END)", 0
        JP      SHOW

; PRRES from HL
PRRESHL:
        PUSH    HL
        LD      DE, RESULT
        OR      A
        SBC     HL, DE
        POP     HL
        JP      PRR1

T_VR:   DB      "S#2 VR", 0

; ------------------------------------------------------------------------- page 4: line int
; IE1 on (CPU interrupts off): iterations from F until S#1 FH for R#19 = 0, 100, 191
PGLINE: CALL    TEXTINIT
        LD      HL, T_LINE
        CALL    HEADER
        CALL    PRINTI
        DB      "F TO FH, R#19 = 0 / 100 / 191:", 0
        CALL    NL
        CALL    SHOW
        LD      C, 0
PL1:    LD      HL, LINETAB
        LD      A, C
        CP      3
        JR      C, PL2
        SUB     3
        CP      3
        JR      C, PL2
        SUB     3
PL2:    LD      E, A
        LD      D, 0
        ADD     HL, DE
        LD      A, (HL)
        PUSH    BC
        CALL    LINEPOS
        POP     BC
        CALL    STORE
        INC     C
        LD      A, C
        CP      9
        JR      NZ, PL1
        LD      HL, RESULT
        LD      B, 3
PL3:    PUSH    BC
        PUSH    HL
        LD      B, 3
        CALL    PRRESHL
        CALL    NL
        POP     HL
        LD      DE, 6
        ADD     HL, DE
        POP     BC
        DJNZ    PL3
        CALL    NL
        CALL    PRINTI
        DB      "MODEL NTSC: 288 695 1066", 0
        CALL    NL
        CALL    PRINTI
        DB      "      PAL:  496 903 1274", 0
        CALL    NL
        CALL    PRINTI
        DB      "(FH AT THE RIGHT BORDER OF", 0
        CALL    NL
        CALL    PRINTI
        DB      " LINE R#19, F AT LINE 192)", 0
        JP      SHOW

LINETAB:
        DB      0, 100, 191

; A = R#19; HL = iterations from F until FH
LINEPOS:
        LD      E, 19
        CALL    WRREG
        LD      A, (RG0)
        OR      10h
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        CALL    WAITF
        LD      A, 1
        CALL    SELST
        IN      A, (VDPC)               ; R#19 = 191 matched before this F
        LD      B, 01h
        CALL    CNTNZ
        PUSH    HL
        XOR     A
        CALL    SELST
        LD      A, (RG0)
        AND     0EFh
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        POP     HL
        RET

T_LINE: DB      "LINE INTERRUPT POSITION", 0

; ------------------------------------------------------------------------- page 5: FH
PGFH:   CALL    TEXTINIT
        LD      HL, T_FH
        CALL    HEADER
        CALL    SHOW
        ; 1: FH (IE1 on, R#19 = 190) read 40 lines after F: must still be 1
        CALL    PRINTI
        DB      "FH R#19=190 READ AFTER F+40:", 0
        LD      C, 0
PF1:    PUSH    BC
        LD      A, 190
        LD      E, 19
        CALL    WRREG
        LD      A, 10h
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        CALL    WAITF
        LD      A, 1                    ; clear FH
        CALL    SELST
        IN      A, (VDPC)
        XOR     A
        CALL    SELST
        CALL    WAITF                   ; line 190 matches before this F
        LD      DE, 304                 ; about 40 lines
        CALL    DELAY
        LD      A, 1
        CALL    SELST
        IN      A, (VDPC)
        PUSH    AF
        XOR     A
        CALL    SELST
        CALL    QUIET
        POP     AF
        CALL    PRBIT
        POP     BC
        INC     C
        LD      A, C
        CP      4
        JR      NZ, PF1
        CALL    NL
        CALL    PRINTI
        DB      " MODEL: 1111", 0
        CALL    NL
        CALL    NL
        ; 2: IE1 off, R#19 = 100: FH reads 1 only on the R#19 line
        CALL    PRINTI
        DB      "IE1 OFF R#19=100: F TO FH=1,", 0
        CALL    NL
        CALL    PRINTI
        DB      "FH=1 TIME, FH AT LINE 110:", 0
        CALL    NL
        LD      C, 0
PF2:    PUSH    BC
        LD      A, 100
        LD      E, 19
        CALL    WRREG
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        CALL    WAITF
        LD      A, 1
        CALL    SELST
        LD      B, 01h
        CALL    CNTNZ
        POP     BC
        PUSH    BC
        CALL    STORE
        LD      B, 01h
        CALL    CNTZ
        POP     BC
        PUSH    BC
        INC     C
        CALL    STORE
        XOR     A                       ; no S#1 read on this frame until line 110
        CALL    SELST
        CALL    WAITF
        CALL    TOLINE110
        CALL    DELAY
        LD      A, 1
        CALL    SELST
        IN      A, (VDPC)
        AND     1
        LD      L, A
        LD      H, 0
        POP     BC
        PUSH    BC
        INC     C
        INC     C
        CALL    STORE
        XOR     A
        CALL    SELST
        POP     BC
        LD      A, C
        ADD     A, 3
        LD      C, A
        CP      9
        JR      NZ, PF2
        LD      HL, RESULT
        LD      B, 3
PF3:    PUSH    BC
        PUSH    HL
        LD      B, 3
        CALL    PRRESHL
        CALL    NL
        POP     HL
        LD      DE, 6
        ADD     HL, DE
        POP     BC
        DJNZ    PF3
        CALL    PRINTI
        DB      " MODEL: (LINE INT 100) 0-1 0", 0
        CALL    NL
        CALL    NL
        ; 3: line 100 passed with IE1 off, then IE1 on: nothing may be latched
        CALL    PRINTI
        DB      "IE1 ON AFTER MATCH: ", 0
        LD      C, 0
PF4:    PUSH    BC
        XOR     A
        CALL    SELST
        IN      A, (VDPC)
        CALL    WAITF
        CALL    TOLINE110
        CALL    DELAY
        LD      A, 10h
        LD      (RG0), A
        LD      E, 0
        CALL    WRREG
        LD      A, 1
        CALL    SELST
        IN      A, (VDPC)
        PUSH    AF
        CALL    QUIET
        POP     AF
        CALL    PRBIT
        POP     BC
        INC     C
        LD      A, C
        CP      4
        JR      NZ, PF4
        CALL    NL
        CALL    PRINTI
        DB      " MODEL: 0000", 0
        JP      SHOW

T_FH:   DB      "S#1 FH", 0

; DE for DELAY from F (line 192) to line 110 of the next frame
TOLINE110:
        LD      DE, 1368                ; NTSC: 70 + 110 lines
        LD      A, (PALB)
        OR      A
        RET     Z
        LD      DE, 1755                ; PAL: 121 + 110 lines
        RET

; ------------------------------------------------------------------------- page 6: 5S, C
; Graphic 1, sprites 8x8 on line 100: five side by side (5S), two overlapping (C).
; Iterations from F until the flag (the polling reads clear it again).
PGSPRT: CALL    TEXTINIT
        LD      HL, T_SPRT
        CALL    HEADER
        CALL    SHOW
        CALL    PRINTI
        DB      "F TO 5S (5 SPRITES Y=99):", 0
        CALL    NL
        LD      HL, SAT5
        LD      BC, 21
        CALL    SETSAT
        LD      C, 0
        LD      B, 40h
        CALL    FLAGPOS
        LD      B, 4
        CALL    PRRES
        CALL    NL
        CALL    NL
        CALL    PRINTI
        DB      "F TO C (2 SPRITES Y=99):", 0
        CALL    NL
        LD      HL, SATC
        LD      BC, 9
        CALL    SETSAT
        LD      C, 0
        LD      B, 20h
        CALL    FLAGPOS
        LD      B, 4
        CALL    PRRES
        CALL    NL
        CALL    NL
        CALL    PRINTI
        DB      "MODEL: NTSC ~688, PAL ~895", 0
        CALL    NL
        CALL    PRINTI
        DB      "(LINE 99 TESTS LINE 100)", 0
        JP      SHOW

; 4 measurements of the S#0 flag B from F, results 0-3
FLAGPOS:
        LD      C, 0
FP1:    PUSH    BC
        IN      A, (VDPC)
        CALL    WAITF
        CALL    CNTNZ
        POP     BC
        PUSH    BC
        CALL    STORE
        POP     BC
        INC     C
        LD      A, C
        CP      4
        JR      NZ, FP1
        RET

; sprite attribute table (Graphic 1) from HL, BC bytes
SETSAT: PUSH    HL
        PUSH    BC
        CALL    DISPOFF
        POP     BC
        POP     HL
        LD      DE, 1B00h
        CALL    LDIRVM
        JP      DISPON

SAT5:   DB      99, 20, 0, 15, 99, 60, 0, 15, 99, 100, 0, 15, 99, 140, 0, 15
        DB      99, 180, 0, 15, 0D0h
SATC:   DB      99, 100, 0, 15, 99, 104, 0, 15, 0D0h

T_SPRT: DB      "5S AND C TIMING", 0

; ------------------------------------------------------------------------- page 7: C window
; Collision flag after one whole frame (all reads ORed): TMS in Graphic 1 (sprite mode 1),
; V99x8 in SCREEN 5 (sprite mode 2). Only display lines may collide.
PGCOLL: CALL    TEXTINIT
        LD      A, (VTYPE)
        OR      A
        JR      Z, PC0
        CALL    G5INIT
PC0:    LD      HL, COLLTAB
        LD      C, 0
PC1:    LD      A, (HL)
        CP      0FFh
        JR      Z, PC9
        INC     HL
        LD      B, (HL)                 ; number of sprites
        INC     HL
        PUSH    HL
        PUSH    BC
        CALL    COLLSET
        IN      A, (VDPC)
        CALL    WAITF
        CALL    ACCF
        POP     BC
        LD      A, (ACC)
        RRCA
        RRCA
        RRCA
        RRCA
        RRCA
        AND     1
        LD      L, A
        LD      H, 0
        CALL    STORE
        POP     HL
        INC     C
        JR      PC1
PC9:    CALL    TEXTINIT
        LD      HL, T_COLL
        CALL    HEADER
        LD      HL, COLLTXT
        LD      C, 0
PC10:   LD      A, (HL)
        OR      A
        JR      Z, PC11
        PUSH    BC
        CALL    PRINT
        PUSH    HL
        POP     HL
        POP     BC
        PUSH    BC
        PUSH    HL
        LD      L, C
        LD      H, 0
        ADD     HL, HL
        LD      DE, RESULT
        ADD     HL, DE
        LD      A, (HL)
        CALL    PRBIT
        CALL    NL
        POP     HL
        POP     BC
        INC     C
        JR      PC10
PC11:   CALL    NL
        CALL    PRINTI
        DB      "MODEL V99X8 (OPENMSX): 11001", 0
        CALL    NL
        CALL    PRINTI
        DB      "M5 TMS9929A HW: Y=191 -> 0", 0
        JP      SHOW

; Y, count; 0FFh end
COLLTAB:
        DB      99, 2, 191, 2, 209, 2, 230, 32, 252, 2, 0FFh
COLLTXT:
        DB      "Y= 99 2 SPRITES  (1): ", 0
        DB      "Y=191 LINE 192   (?): ", 0
        DB      "Y=209 2 SPRITES  (0): ", 0
        DB      "Y=230 32 SPRITES (0): ", 0
        DB      "Y=252 TOP EDGE   (1): ", 0
        DB      0

; A = Y, B = number of sprites at X = 100 / 104 alternating, terminated
COLLSET:
        PUSH    AF
        PUSH    BC
        CALL    DISPOFF
        LD      A, (VTYPE)
        OR      A
        LD      HL, 1B00h
        JR      Z, CS1
        LD      HL, 7600h
CS1:    CALL    SETWR
        POP     BC
        POP     AF
        LD      D, A
        LD      C, 100
CS2:    LD      A, D
        OUT     (VDPD), A
        LD      A, C
        OUT     (VDPD), A
        XOR     A
        OUT     (VDPD), A
        LD      A, 15
        OUT     (VDPD), A
        LD      A, C
        XOR     100 XOR 104
        LD      C, A
        DJNZ    CS2
        LD      A, B
        LD      A, (VTYPE)
        OR      A
        LD      A, 0D0h
        JR      Z, CS3
        LD      A, 0D8h
CS3:    OUT     (VDPD), A
        JP      DISPON

T_COLL: DB      "SPRITE COLLISION WINDOW", 0

; SCREEN 5, sprites 8x8 mode 2: SAT 7600h, colours 7400h, patterns 7800h
G5INIT: CALL    DISPOFF
        LD      HL, G5REGS
G5I1:   LD      E, (HL)
        INC     HL
        LD      A, E
        CP      0FFh
        JR      Z, G5I2
        LD      A, (HL)
        INC     HL
        CALL    WRREG
        JR      G5I1
G5I2:   LD      A, (PALB)
        LD      E, 9
        CALL    WRREG
        LD      A, 06h
        LD      (RG0), A
        LD      A, 0
        LD      (RG1), A
        LD      HL, 0
        LD      BC, 7400h
        LD      D, 0
        CALL    FILVRM
        LD      HL, 7400h               ; sprite colours
        LD      BC, 200h
        LD      D, 0Fh
        CALL    FILVRM
        LD      HL, 7600h
        LD      BC, 1
        LD      D, 0D8h
        CALL    FILVRM
        LD      HL, 7800h
        LD      BC, 8
        LD      D, 0FFh
        CALL    FILVRM
        JP      DISPON

G5REGS: DB      0, 06h, 1, 00h, 2, 1Fh, 5, 0EFh, 11, 0, 6, 0Fh, 7, 04h, 8, 08h
        DB      14, 0, 15, 0, 23, 0, 0FFh

; ------------------------------------------------------------------------- page 8: commands
; SCREEN 5, display on, sprites off: iterations from the command start until CE = 0
PGCMD:  CALL    TEXTINIT
        CALL    G5INIT
        LD      A, 0Ah                  ; sprites off
        LD      E, 8
        CALL    WRREG
        LD      A, 2
        CALL    SELST
        LD      HL, CMDTAB
        LD      C, 0
PM1:    LD      A, (HL)
        CP      0FFh
        JR      Z, PM9
        PUSH    BC
        PUSH    HL
        CALL    CMDRUN
        POP     DE
        POP     BC
        PUSH    DE                      ; STORE changes DE
        CALL    STORE
        POP     DE
        LD      HL, 16
        ADD     HL, DE
        INC     C
        JR      PM1
PM9:    CALL    DISPOFF                 ; HMMV with the display off
        LD      HL, CMDTAB
        CALL    CMDRUN
        LD      C, 7
        CALL    STORE
        XOR     A
        CALL    SELST
        CALL    TEXTINIT
        LD      HL, T_CMD
        CALL    HEADER
        LD      HL, CMDTXT
        LD      C, 0
PM10:   LD      A, (HL)
        OR      A
        JR      Z, PM11
        PUSH    BC
        CALL    PRINT
        POP     BC
        PUSH    BC
        PUSH    HL
        LD      L, C
        LD      H, 0
        ADD     HL, HL
        LD      DE, RESULT
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        CALL    PRNUM
        CALL    NL
        POP     HL
        POP     BC
        INC     C
        JR      PM10
PM11:   CALL    PRINTI
        DB      "(56 T/ITER, ITER*56/228=LINES)", 0
        JP      SHOW

; run the command at HL (R#32-R#46, 15 bytes) and count until CE = 0 (S#2 selected)
CMDRUN: PUSH    HL
        LD      A, 32
        LD      E, 17
        CALL    WRREG
        POP     HL
        LD      B, 15
        LD      C, VDPI
        OTIR
        LD      B, 01h
        JP      CNTZ

; SX, SY, DX, DY, NX, NY (words), CLR, ARG, CMD, pad
CMDTAB: DW      0, 0, 0, 0, 256, 212
        DB      44h, 0, 0C0h, 0             ; HMMV
        DW      0, 0, 0, 0, 256, 212
        DB      05h, 0, 80h, 0              ; LMMV
        DW      0, 256, 0, 0, 256, 212
        DB      0, 0, 0E0h, 0               ; YMMM
        DW      0, 256, 0, 0, 256, 212
        DB      0, 0, 0D0h, 0               ; HMMM
        DW      0, 256, 0, 0, 256, 212
        DB      0, 0, 90h, 0                ; LMMM
        DW      0, 0, 0, 0, 255, 100
        DB      0Fh, 0, 70h, 0              ; LINE
        DW      0, 0, 0, 0, 255, 255
        DB      0Fh, 0, 70h, 0              ; LINE, 255 x 255 (diagonal)
        DB      0FFh

CMDTXT: DB      "HMMV 256X212        ", 0
        DB      "LMMV 256X212        ", 0
        DB      "YMMM 212 LINES      ", 0
        DB      "HMMM 256X212        ", 0
        DB      "LMMM 256X212        ", 0
        DB      "LINE 255,100        ", 0
        DB      "LINE 255,255        ", 0
        DB      "HMMV, DISPLAY OFF   ", 0
        DB      0

T_CMD:  DB      "VDP COMMAND TIME", 0

        DS      8000h - $, 0FFh
