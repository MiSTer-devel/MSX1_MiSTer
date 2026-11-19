; MEMPTR (WZ) test program for z80_undoc_tb (Z80): after each tested instruction BIT 0,(HL)
; shows bits 13 and 11 of MEMPTR as flags Y and X; the flags go to RESULT + n, the expected high
; byte of MEMPTR (openMSX CPUCore setMemPtr) is in EXP + n. Addresses cross a 256 byte page so
; that +1 / -1 mistakes change Y / X. Build (Git Bash): sh rtl/tb/z80_memptr.sh

RESULT     EQU     0C000h
EXP     EQU     0C100h          ; filled by the copy loop at the end
PROBEB  EQU     03000h          ; holds 01h

PROBE   MACRO   num
        LD      HL, PROBEB
        BIT     0, (HL)
        PUSH    AF
        POP     DE
        LD      A, E
        LD      (RESULT + num), A
        ENDM

M0800   MACRO                   ; MEMPTR = 0800h
        LD      A, (07FFh)
        ENDM
M2000   MACRO                   ; MEMPTR = 2000h
        LD      A, (1FFFh)
        ENDM
M2800   MACRO                   ; MEMPTR = 2800h
        LD      A, (27FFh)
        ENDM

        ORG     0
        JP      START
        DS      5, 0
        ; RST 08h lands here: MEMPTR = 0008h
        PROBE   16
        JP      AFTER16

        ORG     0100h
START:  DI
        LD      SP, 0F000h
        LD      A, 1
        LD      (PROBEB), A

        M0800
        LD      A, (27FFh)              ; 0: nn + 1
        PROBE   0
        M2800
        LD      A, 08h
        LD      (12FFh), A              ; 1: A : (n + 1)
        PROBE   1
        M0800
        LD      BC, 27FFh
        LD      A, (BC)                 ; 2: BC + 1
        PROBE   2
        M0800
        LD      DE, 07FFh
        LD      A, 20h
        LD      (DE), A                 ; 3: A : (E + 1)
        PROBE   3
        M0800
        LD      HL, (1FFFh)             ; 4: nn + 1
        PROBE   4
        M2800
        LD      (07FFh), HL             ; 5: nn + 1
        PROBE   5
        M0800
        LD      BC, (27FFh)             ; 6: ED 4B, nn + 1
        PROBE   6
        M0800
        LD      (1FFFh), DE             ; 7: ED 53, nn + 1
        PROBE   7
        M0800
        JP      L8                      ; 8: nn

        ORG     2400h                   ; CALL SUB11: MEMPTR = 2400h
SUB11:  PROBE   11
        RET

        ORG     2800h
L8:     PROBE   8
        M0800
        XOR     A
        JP      NZ, 2000h               ; 9: not taken: nn
        PROBE   9
        M2800
        OR      A
        CALL    C, 0800h                ; 10: not taken: nn
        PROBE   10
        M0800
        CALL    SUB11                   ; 11: nn (probe in SUB11)
        PROBE   12                      ; 12: RET: return address
        M2000
        JR      L13                     ; 13: taken: target
L13:    PROBE   13
        M2000
        SCF
        JR      NC, L14                 ; 14: not taken: unchanged
L14:    PROBE   14
        M2000
        LD      B, 2
        DJNZ    L15                     ; 15: taken: target
L15:    PROBE   15
        M2800
        RST     08h                     ; 16: 0008h (probe at 0008h)
AFTER16:
        LD      HL, 2800h
        PUSH    HL
        M0800
        EX      (SP), HL                ; 17: the new HL
        PROBE   17
        POP     HL
        M0800
        LD      HL, 27FFh
        LD      BC, 1
        ADD     HL, BC                  ; 18: HL + 1
        PROBE   18
        M0800
        LD      HL, 1FFFh
        LD      DE, 1
        ADC     HL, DE                  ; 19: HL + 1
        PROBE   19
        M2800
        LD      HL, 07FFh
        OR      A
        SBC     HL, DE                  ; 20: HL + 1
        PROBE   20
        M0800
        LD      A, 27h
        IN      A, (0FFh)               ; 21: A : n + 1
        PROBE   21
        M2800
        LD      A, 08h
        OUT     (0FFh), A               ; 22: A : (n + 1)
        PROBE   22
        M0800
        LD      BC, 27FFh
        IN      D, (C)                  ; 23: BC + 1
        PROBE   23
        M2800
        LD      BC, 07FFh
        OUT     (C), A                  ; 24: BC + 1
        PROBE   24
        M0800
        LD      HL, 27FFh
        RLD                             ; 25: HL + 1
        PROBE   25
        M2000
        LD      HL, 3100h
        LD      DE, 3200h
        LD      BC, 2
L26:    LDIR                            ; 26: repeat: its address + 1
        PROBE   26
        M2000
        LD      BC, 2
        LDI                             ; 27: unchanged
        PROBE   27
        LD      A, (27FEh)              ; MEMPTR = 27FFh
        CPI                             ; 28: + 1
        PROBE   28
        M2800
        CPD                             ; 29: - 1
        PROBE   29
        M0800
        LD      A, 0FFh
        LD      HL, 3100h
        LD      BC, 2
        CPIR                            ; 30: repeat, then + 1
        PROBE   30
        M0800
        LD      HL, 3300h
        LD      BC, 27FFh
        INI                             ; 31: BC + 1
        PROBE   31
        M0800
        LD      BC, 2800h
        IND                             ; 32: BC - 1
        PROBE   32
        M2800
        LD      HL, 3100h
        LD      BC, 0800h
        OUTI                            ; 33: (B - 1, C) + 1
        PROBE   33
        M2800
        LD      BC, 0800h
        OUTD                            ; 34: (B - 1, C) - 1
        PROBE   34
        M0800
        LD      IX, 27F0h
        LD      A, (IX + 10h)           ; 35: IX + d
        PROBE   35
        M0800
        LD      IY, 1FF0h
        LD      (IY + 10h), 5           ; 36: IY + d
        PROBE   36
        M0800
        LD      IX, 27F0h
        BIT     0, (IX + 10h)           ; 37: DDCB BIT: X / Y of IX + d itself
        PUSH    AF
        POP     DE
        LD      HL, RESULT + 37            ; (LD (nn),A would set MEMPTR)
        LD      (HL), E
        PROBE   38                      ; 38: MEMPTR = IX + d
        M0800
        LD      IX, 1FF0h
        SET     0, (IX + 10h)           ; 39: IX + d
        PROBE   39

        LD      HL, EXPTAB              ; expected values to EXP
        LD      DE, EXP
        LD      BC, NTEST
        LDIR
        OUT     (34h), A                ; end mark for the tb
        HALT

EXPTAB: DB      28h, 08h, 28h, 20h, 20h, 08h, 28h, 20h, 28h, 20h        ; 0-9
        DB      08h, 24h, 28h, 28h, 20h, 28h, 00h, 28h, 28h, 20h        ; 10-19
        DB      08h, 28h, 08h, 28h, 08h, 28h, 28h, 20h, 28h, 27h        ; 20-29
        DB      28h, 28h, 27h, 07h, 06h, 28h, 20h, 28h, 28h, 20h        ; 30-39
NTEST   EQU     $ - EXPTAB

