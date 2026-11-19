; MIDITEST for MSX - MSX-MIDI output test (MT32-pi, MidiLink) with a picture of what plays
;
; Copyright (c) 2026 Molekula
; SPDX-License-Identifier: GPL-3.0-or-later
;
; 16 kB cartridge ROM at 4000h. Sends MIDI through MSX-MIDI (8251 + 8254 at E8h, built in on
; the FS-A1GT, or the MSX-MIDI cartridge) on channels 2-10: the MT-32 parts 1-8 and the
; rhythm part. Every channel has a row with the instrument, the last note and velocity and a
; lane with all 128 notes (2 pixels each) over a keyboard.
;
; Modes: F1 song, F2 instrument sweep (channel 2, programs 0-127), F3 drum sweep (channel 10),
;        F4 live keyboard (channel 2). F5 switches the map MT-32 / GM and sends the mt32-pi
;        SysEx "switch synth". R / S (not in F4) send "switch ROM set" / "switch SoundFont".
;        SPACE pause, ESC all notes off, cursor keys per mode (status line).
;
; Build: build.sh (gen_data.py -> data.inc, pasmo).

MIDID   EQU     0E8h            ; 8251 data
MIDIC   EQU     0E9h            ; 8251 mode / command / status
TMR0    EQU     0ECh            ; 8254 counter 0 (TxC of the 8251)
TMRC    EQU     0EFh            ; 8254 control word

VDPD    EQU     98h
VDPC    EQU     99h
PPIB    EQU     0A9h            ; keyboard columns
PPIC    EQU     0AAh            ; keyboard row (low nibble)

CGTABL  EQU     0004h           ; BIOS: font address
MSXVER  EQU     002Dh           ; BIOS: 3 = turbo R
DISSCR  EQU     0041h
ENASCR  EQU     0044h
INIGRP  EQU     0072h           ; SCREEN 2
CHGCPU  EQU     0180h           ; turbo R
CLIKSW  EQU     0F3DBh
FORCLR  EQU     0F3E9h
BAKCLR  EQU     0F3EAh
BDRCLR  EQU     0F3EBh
JIFFY   EQU     0FC9Eh

; VRAM of SCREEN 2 (INIGRP)
VPAT    EQU     0000h
VNAM    EQU     1800h
VCOL    EQU     2000h
VSAT    EQU     1B00h

NSLOT   EQU     9               ; MIDI channels 2-10
PROLL   EQU     96              ; lane patterns: + slot * 16 + 4 notes
PKEY    EQU     240             ; 3 keyboard tiles
PLEG    EQU     243             ; + slot: channel colour block
NKEYS   EQU     28              ; live keys
P0      EQU     16              ; patterns of "0", "1", "-" (pasmo: no character arithmetic)
P1      EQU     17
PDASH   EQU     13

; RAM
LASTST  EQU     0E000h          ; running status (0 = none)
MIDIOK  EQU     0E001h
MODE    EQU     0E002h
MAP     EQU     0E003h          ; 0 MT-32, 1 GM
PAUSED  EQU     0E004h
SPEED   EQU     0E005h          ; frames per step
FRAMES  EQU     0E006h
LASTJ   EQU     0E007h
WAIT    EQU     0E008h
SPTR    EQU     0E009h          ; stream pointer (0 = none)
SSTART  EQU     0E00Bh
INSTPRG EQU     0E00Dh
DRUMKEY EQU     0E00Eh
KEYPRG  EQU     0E00Fh
OCTAVE  EQU     0E010h
STDIRTY EQU     0E011h
RESEND  EQU     0E012h          ; frames until the programs are sent again
ROMSET  EQU     0E013h          ; FFh = not sent
SFONT   EQU     0E014h
LSEMI   EQU     0E015h
DIRTY   EQU     0E020h          ; per slot: bit 0 lane, bit 1 text
PROG    EQU     0E030h
LNOTE   EQU     0E040h          ; FFh = none
LVEL    EQU     0E050h
KOLD    EQU     0E060h          ; keyboard matrix rows 0-8
KNEW    EQU     0E070h
KEYNOTE EQU     0E080h          ; note sent by each live key, FFh = none
LINE    EQU     0E0C0h          ; 32 patterns
NOTES   EQU     0E100h          ; 9 x 16 bytes: bit k of byte b = note 8b + k
STACK   EQU     0EF00h

        ORG     4000h
        DB      "AB"
        DW      START
        DW      0, 0, 0
        DS      6, 0

; ------------------------------------------------------------------------- start
START:  DI
        LD      SP, STACK
        LD      A, (MSXVER)
        CP      3
        JR      NZ, NOTR
        XOR     A                       ; turbo R: Z80 (VDP access timing of an MSX)
        CALL    CHGCPU
NOTR:   DI
        XOR     A
        LD      (CLIKSW), A
        LD      A, 15
        LD      (FORCLR), A
        LD      A, 1
        LD      (BAKCLR), A
        LD      (BDRCLR), A
        CALL    INIGRP
        CALL    DISSCR
        DI
        CALL    SETVRAM
        ; RAM
        LD      HL, 0E000h
        LD      DE, 0E001h
        LD      BC, 01FFh
        LD      (HL), 0
        LDIR
        LD      HL, LNOTE
        LD      B, NSLOT
        CALL    FILLFF
        LD      HL, KOLD
        LD      B, 9
        CALL    FILLFF
        LD      HL, KEYNOTE
        LD      B, NKEYS
        CALL    FILLFF
        LD      A, 0FFh
        LD      (ROMSET), A
        LD      (SFONT), A
        LD      A, 7
        LD      (SPEED), A
        LD      A, 4
        LD      (OCTAVE), A
        LD      A, 35
        LD      (DRUMKEY), A
        LD      A, (JIFFY)
        LD      (LASTJ), A
        CALL    MIDIINIT
        CALL    DRAWSTATIC
        XOR     A
        CALL    SETMODE
        CALL    REDRAW
        CALL    ENASCR

; ------------------------------------------------------------------------- main loop
MAIN:   EI
        HALT
        LD      A, (JIFFY)
        LD      HL, LASTJ
        LD      B, A
        SUB     (HL)
        JR      Z, MAIN
        LD      (HL), B
        CP      5                       ; catch up at most 4 frames
        JR      C, MAIN1
        LD      A, 4
MAIN1:  LD      C, A
        PUSH    BC
        CALL    KEYS
        POP     BC
        LD      A, (RESEND)             ; waiting for the synth after a switch
        OR      A
        JR      Z, MAIN2
        SUB     C
        JR      Z, MAINRS
        JR      NC, MAINRW
MAINRS: XOR     A
        LD      (RESEND), A
        INC     A
        LD      (STDIRTY), A
        CALL    SENDPROGS
        JR      MAINDR
MAINRW: LD      (RESEND), A
        JR      MAINDR
MAIN2:  LD      A, (PAUSED)
        OR      A
        JR      NZ, MAINDR
        LD      A, (FRAMES)
        ADD     A, C
MAINTK: LD      HL, SPEED
        CP      (HL)
        JR      C, MAINFR
        SUB     (HL)
        LD      (FRAMES), A
        CALL    STEP
        LD      A, (FRAMES)
        JR      MAINTK
MAINFR: LD      (FRAMES), A
MAINDR: CALL    REDRAW
        JR      MAIN

FILLFF: LD      (HL), 0FFh
        INC     HL
        DJNZ    FILLFF
        RET

; ------------------------------------------------------------------------- MIDI
; 8254 counter 0: mode 3, 4 MHz / 8 = 500 kHz = 16 x 31250. 8251: reset, x16, 8N1, TxEN RxE ER
; (DTR and RTS off: no interrupts).
MIDIINIT:
        LD      A, 36h
        OUT     (TMRC), A
        LD      A, 8
        OUT     (TMR0), A
        XOR     A
        OUT     (TMR0), A
        LD      HL, MINITSEQ
        LD      B, 6
MINIT1: LD      A, (HL)
        OUT     (MIDIC), A
        INC     HL
        EX      (SP), HL                ; recovery time
        EX      (SP), HL
        DJNZ    MINIT1
        IN      A, (MIDIC)
        LD      B, A
        AND     38h                     ; no PE / OE / FE after ER (FFh = no device)
        RET     NZ
        LD      A, B
        AND     01h                     ; TxRDY
        LD      (MIDIOK), A
        RET
MINITSEQ:
        DB      00h, 00h, 00h, 40h, 4Eh, 15h

; A -> MIDI
MOUT:   PUSH    BC
        LD      C, A
        LD      A, (MIDIOK)
        OR      A
        JR      Z, MOUTX
        LD      B, 0
MOUTW:  IN      A, (MIDIC)
        RRCA
        JR      C, MOUTGO
        DJNZ    MOUTW                   ; timeout ~2.7 ms, then send anyway
MOUTGO: LD      A, C
        OUT     (MIDID), A
MOUTX:  POP     BC
        RET

; channel message A = status, D, E (running status)
MCH3:   CALL    MSTAT
        LD      A, D
        CALL    MOUT
        LD      A, E
        JR      MOUT
; channel message A = status, D
MCH2:   CALL    MSTAT
        LD      A, D
        JR      MOUT
MSTAT:  LD      HL, LASTST
        CP      (HL)
        RET     Z
        LD      (HL), A
        JR      MOUT

; SysEx F0 7D A E F7 (mt32-pi)
MT32PI: PUSH    AF
        LD      A, 0F0h
        CALL    MOUT
        LD      A, 7Dh
        CALL    MOUT
        POP     AF
        CALL    MOUT
        LD      A, E
        CALL    MOUT
        LD      A, 0F7h
        CALL    MOUT
        XOR     A
        LD      (LASTST), A
        LD      A, 30                   ; programs again after 0.5 s
        LD      (RESEND), A
        LD      A, 1
        LD      (STDIRTY), A
        RET

; note event A = status (9n), D = note, E = velocity; updates the picture of slot n-1
NOTEV:  LD      B, A
        AND     0Fh
        DEC     A
        CP      NSLOT
        JR      NC, NOTEVX
        LD      C, A                    ; slot
        CP      8
        JR      NZ, NOTEV1
        LD      A, D
        OR      A
        JR      NZ, NOTEV1
        LD      A, (DRUMKEY)            ; drum sweep: note 0 = current key
        LD      D, A
NOTEV1: LD      A, B
        PUSH    BC
        CALL    MCH3
        POP     BC
        CALL    NBIT
        LD      B, A
        LD      A, E
        OR      A
        JR      Z, NOTEVF
        LD      A, B
        OR      (HL)
        LD      (HL), A
        LD      HL, LNOTE
        CALL    SLOTHL
        LD      (HL), D
        LD      HL, LVEL
        CALL    SLOTHL
        LD      (HL), E
        LD      A, 3
        JR      SETDIRTY
NOTEVF: LD      A, B
        CPL
        AND     (HL)
        LD      (HL), A
        LD      A, 1
        JR      SETDIRTY
NOTEVX: LD      A, B
        JP      MCH3

; DIRTY[C] |= A
SETDIRTY:
        LD      HL, DIRTY
        CALL    SLOTHL
        OR      (HL)
        LD      (HL), A
        RET

; HL += C
SLOTHL: PUSH    AF
        LD      A, L
        ADD     A, C
        LD      L, A
        JR      NC, SLOTH1
        INC     H
SLOTH1: POP     AF
        RET

; slot C, note D -> HL = byte in NOTES, A = bit mask
NBIT:   LD      A, C
        ADD     A, A
        ADD     A, A
        ADD     A, A
        ADD     A, A
        LD      L, A
        LD      A, D
        RRCA
        RRCA
        RRCA
        AND     0Fh
        ADD     A, L
        LD      L, A
        LD      H, NOTES / 256
        LD      A, D
        AND     7
        LD      B, A
        LD      A, 1
        RET     Z
NBIT1:  ADD     A, A
        DJNZ    NBIT1
        RET

; all notes off on channels 2-10, clear the lanes and the live keys
ALLOFF: LD      C, 0
ALLOF1: LD      A, C
        INC     A
        OR      0B0h
        PUSH    BC
        LD      D, 123                  ; All Notes Off
        LD      E, 0
        CALL    MCH3
        POP     BC
        LD      A, 1
        CALL    SETDIRTY
        INC     C
        LD      A, C
        CP      NSLOT
        JR      C, ALLOF1
        LD      HL, NOTES
        LD      DE, NOTES + 1
        LD      BC, NSLOT * 16 - 1
        LD      (HL), 0
        LDIR
        LD      HL, KEYNOTE
        LD      B, NKEYS
        JP      FILLFF

; reset controllers, volume, pan, program on channels 2-10
SENDPROGS:
        LD      C, 0
SENDP1: LD      A, C
        INC     A
        OR      0B0h
        LD      B, A
        PUSH    BC
        LD      D, 121                  ; Reset All Controllers
        LD      E, 0
        CALL    MCH3
        POP     BC
        PUSH    BC
        LD      A, B
        LD      D, 7                    ; volume
        LD      E, 100
        CALL    MCH3
        POP     BC
        PUSH    BC
        LD      HL, PANTAB
        CALL    SLOTHL
        LD      E, (HL)
        LD      A, B
        LD      D, 10                   ; pan
        CALL    MCH3
        POP     BC
        LD      A, C
        CP      8
        JR      Z, SENDP2               ; rhythm part: no program
        LD      HL, PROG
        CALL    SLOTHL
        LD      D, (HL)
        LD      A, B
        ADD     A, 10h                  ; Cn
        PUSH    BC
        CALL    MCH2
        POP     BC
SENDP2: LD      A, 2
        CALL    SETDIRTY
        INC     C
        LD      A, C
        CP      NSLOT
        JR      C, SENDP1
        RET
PANTAB: DB      64, 44, 84, 64, 28, 100, 76, 52, 64

; program change on slot 0 (channel 2) to A
PROG0:  LD      (PROG), A
        LD      D, A
        LD      A, 0C1h
        CALL    MCH2
        LD      C, 0
        LD      A, 2
        CALL    SETDIRTY
        LD      A, 1
        LD      (STDIRTY), A
        RET

; ------------------------------------------------------------------------- modes
; A = mode
SETMODE:
        PUSH    AF
        CALL    ALLOFF
        POP     AF
        LD      (MODE), A
        XOR     A
        LD      (PAUSED), A
        LD      (FRAMES), A
        LD      HL, 0
        LD      (SPTR), HL
        LD      HL, LNOTE               ; no last notes
        LD      B, NSLOT
        CALL    FILLFF
        ; song programs of the map
        LD      HL, PROG_MT
        LD      A, (MAP)
        OR      A
        JR      Z, SETM1
        LD      HL, PROG_GM
SETM1:  LD      DE, PROG
        LD      BC, NSLOT
        LDIR
        LD      A, (MODE)
        LD      HL, SONG
        OR      A
        JR      Z, SETMS
        LD      HL, INSTS
        DEC     A
        JR      Z, SETMI
        LD      HL, DRUMS
        DEC     A
        JR      Z, SETMS
        LD      A, (KEYPRG)             ; live keys: no stream
        LD      (PROG), A
        JR      SETMP
SETMI:  LD      A, (INSTPRG)
        LD      (PROG), A
SETMS:  LD      (SSTART), HL
        LD      A, (HL)
        INC     HL
        LD      (WAIT), A
        LD      (SPTR), HL
SETMP:  CALL    SENDPROGS
        LD      A, 1
        LD      (STDIRTY), A
        RET

; end of a stream: next program / drum key
LOOPCB: LD      A, (MODE)
        DEC     A
        JR      NZ, LOOPC1
        LD      A, (INSTPRG)
        INC     A
        AND     7Fh
        LD      (INSTPRG), A
        JP      PROG0
LOOPC1: DEC     A
        RET     NZ
        LD      A, (DRUMKEY)
        INC     A
DRUMSET:
        CP      82
        JR      C, DRUMS1
        LD      A, 35
DRUMS1: CP      35
        JR      NC, DRUMS2
        LD      A, 81
DRUMS2: LD      (DRUMKEY), A
        LD      A, 1
        LD      (STDIRTY), A
        RET

; one step (1/16 note) of the stream
STEP:   LD      HL, (SPTR)
        LD      A, H
        OR      L
        RET     Z
        LD      A, (WAIT)
        OR      A
        JR      Z, STEPGO
        DEC     A
        LD      (WAIT), A
        RET     NZ
STEPGO: LD      HL, (SPTR)
STEPG1: LD      A, (HL)
        INC     HL
        CP      0FFh
        JR      Z, STEPLP
        LD      B, A
STEPEV: PUSH    BC
        LD      A, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        LD      E, (HL)
        INC     HL
        PUSH    HL
        CALL    NOTEV
        POP     HL
        POP     BC
        DJNZ    STEPEV
STEPDL: LD      A, (HL)
        INC     HL
        OR      A
        JR      Z, STEPG1
        LD      (WAIT), A
        LD      (SPTR), HL
        RET
STEPLP: CALL    LOOPCB
        LD      HL, (SSTART)
        JR      STEPDL

; ------------------------------------------------------------------------- keyboard
; matrix rows 0-8 -> KNEW, act on new presses, KNEW -> KOLD
KEYS:   LD      HL, KNEW
        LD      C, 0
KEYS1:  DI
        IN      A, (PPIC)
        AND     0F0h
        OR      C
        OUT     (PPIC), A
        IN      A, (PPIB)
        EI
        LD      (HL), A
        INC     HL
        INC     C
        LD      A, C
        CP      9
        JR      C, KEYS1
        LD      HL, KEYACT
KEYS2:  LD      A, (HL)
        CP      0FFh
        JR      Z, KEYS4
        LD      C, A
        INC     HL
        LD      B, (HL)                 ; mask
        INC     HL
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        INC     HL
        PUSH    HL
        PUSH    DE
        CALL    PRESSED
        POP     HL                      ; handler
        JR      Z, KEYS3
        LD      DE, KEYS3
        PUSH    DE
        JP      (HL)
KEYS3:  POP     HL
        JR      KEYS2
KEYS4:  LD      A, (MODE)
        CP      3
        CALL    Z, LIVE
        LD      HL, KNEW
        LD      DE, KOLD
        LD      BC, 9
        LDIR
        RET

; row C, mask B: NZ = pressed now and not before
PRESSED:
        LD      HL, KNEW
        CALL    SLOTHL
        LD      A, (HL)
        CPL
        LD      DE, KOLD - KNEW
        ADD     HL, DE
        AND     (HL)
        AND     B
        RET

KEYACT: DB      6, 20h
        DW      KF1
        DB      6, 40h
        DW      KF2
        DB      6, 80h
        DW      KF3
        DB      7, 01h
        DW      KF4
        DB      7, 02h
        DW      KF5
        DB      7, 04h
        DW      KESC
        DB      8, 01h
        DW      KSPACE
        DB      8, 10h
        DW      KLEFT
        DB      8, 80h
        DW      KRIGHT
        DB      8, 20h
        DW      KUP
        DB      8, 40h
        DW      KDOWN
        DB      4, 80h
        DW      KR
        DB      5, 01h
        DW      KS
        DB      0FFh

KF1:    XOR     A
        JP      SETMODE
KF2:    LD      A, 1
        JP      SETMODE
KF3:    LD      A, 2
        JP      SETMODE
KF4:    LD      A, 3
        JP      SETMODE
KF5:    CALL    ALLOFF
        LD      A, (MAP)
        XOR     1
        LD      (MAP), A
        LD      E, A
        LD      A, 3                    ; switch synth: 0 MT-32, 1 SoundFont
        CALL    MT32PI
        LD      A, (MODE)
        JP      SETMODE                 ; programs of the map (sent again by RESEND)
KESC:   JP      ALLOFF
KSPACE: LD      A, (MODE)
        CP      3
        RET     Z
        LD      A, (PAUSED)
        XOR     1
        LD      (PAUSED), A
        LD      A, 1
        LD      (STDIRTY), A
        JP      ALLOFF
KR:     LD      A, (MODE)
        CP      3
        RET     Z
        CALL    ALLOFF
        LD      A, (ROMSET)
        INC     A
        CP      3
        JR      C, KR1
        XOR     A
KR1:    LD      (ROMSET), A
        LD      E, A
        LD      A, 1                    ; switch ROM set: old, new, CM-32L
        JP      MT32PI
KS:     LD      A, (MODE)
        CP      3
        RET     Z
        CALL    ALLOFF
        LD      A, (SFONT)
        INC     A
        AND     07h
        LD      (SFONT), A
        LD      E, A
        LD      A, 2                    ; switch SoundFont
        JP      MT32PI

KLEFT:  LD      B, -1
        JR      KLR
KRIGHT: LD      B, 1
KLR:    LD      A, (MODE)
        OR      A
        RET     Z
        DEC     A
        JR      NZ, KLR2
        LD      A, (INSTPRG)            ; instruments: program
        ADD     A, B
        AND     7Fh
        LD      (INSTPRG), A
        JP      PROG0
KLR2:   DEC     A
        JR      NZ, KLR3
        PUSH    BC                      ; drums: key
        CALL    ALLOFF
        POP     BC
        LD      A, (DRUMKEY)
        ADD     A, B
        JP      DRUMSET
KLR3:   LD      A, (OCTAVE)             ; keys: octave 0-8
        ADD     A, B
        CP      9
        RET     NC
        LD      (OCTAVE), A
        LD      A, 1
        LD      (STDIRTY), A
        RET

KUP:    LD      B, -1
        JR      KUD
KDOWN:  LD      B, 1
KUD:    LD      A, (MODE)
        OR      A
        JR      NZ, KUD2
        LD      A, (SPEED)              ; song: frames per step 2-20
        ADD     A, B
        CP      2
        RET     C
        CP      21
        RET     NC
        LD      (SPEED), A
        LD      A, 1
        LD      (STDIRTY), A
        RET
KUD2:   CP      3
        RET     NZ
        LD      A, B                    ; keys: up = next program
        NEG
        LD      B, A
        LD      A, (KEYPRG)
        ADD     A, B
        AND     7Fh
        LD      (KEYPRG), A
        JP      PROG0

; live keyboard on channel 2
LIVE:   LD      HL, LIVEKEYS
        LD      IX, KEYNOTE
LIVE1:  LD      C, (HL)                 ; row
        INC     HL
        LD      B, (HL)                 ; mask
        INC     HL
        LD      A, (HL)                 ; semitone
        LD      (LSEMI), A
        INC     HL
        PUSH    HL
        PUSH    BC
        CALL    PRESSED
        POP     BC
        JR      NZ, LIVEON
        LD      HL, KOLD                ; released?
        CALL    SLOTHL
        LD      A, (HL)
        CPL
        LD      DE, KNEW - KOLD
        ADD     HL, DE
        AND     (HL)
        AND     B
        JR      Z, LIVENX
        LD      A, (IX+0)
        CP      0FFh
        JR      Z, LIVENX
        LD      D, A
        LD      (IX+0), 0FFh
        LD      E, 0
        JR      LIVESN
LIVEON: LD      A, (OCTAVE)
        LD      B, A
        ADD     A, A
        ADD     A, B
        ADD     A, A
        ADD     A, A                    ; * 12
        ADD     A, 12
        LD      HL, LSEMI
        ADD     A, (HL)
        CP      128
        JR      NC, LIVENX
        LD      D, A
        LD      (IX+0), A
        LD      E, 100
LIVESN: LD      A, 91h
        PUSH    IX
        CALL    NOTEV
        POP     IX
LIVENX: POP     HL
        INC     IX
        LD      A, (HL)
        CP      0FFh
        JR      NZ, LIVE1
        RET

; row, mask, semitone: Z S X D C V G B H N J M , L .  /  Q 2 W 3 E R 5 T 6 Y 7 U I
LIVEKEYS:
        DB      5, 80h, 0,  5, 01h, 1,  5, 20h, 2,  3, 02h, 3,  3, 01h, 4,  5, 08h, 5
        DB      3, 10h, 6,  2, 80h, 7,  3, 20h, 8,  4, 08h, 9,  3, 80h, 10, 4, 04h, 11
        DB      2, 04h, 12, 4, 02h, 13, 2, 08h, 14
        DB      4, 40h, 12, 0, 04h, 13, 5, 10h, 14, 0, 08h, 15, 3, 04h, 16, 4, 80h, 17
        DB      0, 20h, 18, 5, 02h, 19, 0, 40h, 20, 5, 40h, 21, 0, 80h, 22, 5, 04h, 23
        DB      3, 40h, 24
        DB      0FFh

; ------------------------------------------------------------------------- VRAM
; HL = VRAM address for writing (interrupts off)
VWADDR: LD      A, L
        OUT     (VDPC), A
        LD      A, H
        AND     3Fh
        OR      40h
        OUT     (VDPC), A
        RET

; patterns and colours of the three thirds, sprites off (screen off)
SETVRAM:
        LD      HL, VSAT
        CALL    VWADDR
        LD      A, 0D0h
        OUT     (VDPD), A
        LD      HL, VPAT
        CALL    PATS
        LD      HL, VPAT + 0800h
        CALL    PATS
        LD      HL, VPAT + 1000h
        CALL    PATS
        LD      HL, VCOL
        CALL    COLS
        LD      HL, VCOL + 0800h
        CALL    COLS
        LD      HL, VCOL + 1000h
        CALL    COLS
        RET

PATS:   CALL    VWADDR
        LD      HL, (CGTABL)            ; ASCII 32-127 -> patterns 0-95
        LD      DE, 32 * 8
        ADD     HL, DE
        LD      BC, 96 * 8
PATS1:  LD      A, (HL)
        OUT     (VDPD), A
        INC     HL
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, PATS1
        LD      C, NSLOT                ; lanes: 9 x 16 masks
PATS2:  LD      HL, MASKB
        LD      B, 16
PATS3:  XOR     A
        OUT     (VDPD), A
        LD      A, (HL)
        LD      E, 6
PATS4:  OUT     (VDPD), A
        DEC     E
        JR      NZ, PATS4
        XOR     A
        OUT     (VDPD), A
        INC     HL
        DJNZ    PATS3
        DEC     C
        JR      NZ, PATS2
        LD      HL, KEYPAT              ; keyboard
        LD      B, 3
PATS5:  LD      A, (HL)
        LD      E, 6
PATS6:  OUT     (VDPD), A
        DEC     E
        JR      NZ, PATS6
        XOR     A
        OUT     (VDPD), A
        OUT     (VDPD), A
        INC     HL
        DJNZ    PATS5
        LD      B, NSLOT                ; colour blocks
PATS7:  XOR     A
        OUT     (VDPD), A
        LD      A, 7Eh
        LD      E, 6
PATS8:  OUT     (VDPD), A
        DEC     E
        JR      NZ, PATS8
        XOR     A
        OUT     (VDPD), A
        DJNZ    PATS7
        LD      B, (256 - PLEG - NSLOT) * 8
PATS9:  OUT     (VDPD), A
        DJNZ    PATS9
        RET

COLS:   CALL    VWADDR
        LD      BC, 96 * 8              ; text: white on black
COLS1:  LD      A, 0F1h
        OUT     (VDPD), A
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, COLS1
        LD      HL, CHCOL               ; lanes: channel colour on dark blue
        LD      C, NSLOT
COLS2:  LD      A, (HL)
        OR      04h
        LD      B, 16 * 8
COLS3:  OUT     (VDPD), A
        DJNZ    COLS3
        INC     HL
        DEC     C
        JR      NZ, COLS2
        LD      A, 0F1h                 ; keyboard
        LD      B, 3 * 8
COLS4:  OUT     (VDPD), A
        DJNZ    COLS4
        LD      HL, CHCOL               ; colour blocks
        LD      C, NSLOT
COLS5:  LD      A, (HL)
        OR      01h
        LD      B, 8
COLS6:  OUT     (VDPD), A
        DJNZ    COLS6
        INC     HL
        DEC     C
        JR      NZ, COLS5
        LD      A, 0F1h
        LD      B, (256 - PLEG - NSLOT) * 8
COLS7:  OUT     (VDPD), A
        DJNZ    COLS7
        RET

; 4 notes per tile, lowest note left, 2 pixels each
MASKB:  DB      00h, 0C0h, 30h, 0F0h, 0Ch, 0CCh, 3Ch, 0FCh
        DB      03h, 0C3h, 33h, 0F3h, 0Fh, 0CFh, 3Fh, 0FFh
; tiles of notes 4t..4t+3 for t mod 3 = 0 (C C# D D#), 1 (E F F# G), 2 (G# A A# B)
KEYPAT: DB      0CCh, 0F3h, 33h
; colour of each channel (high nibble)
CHCOL:  DB      0B0h, 0F0h, 070h, 090h, 030h, 0A0h, 0D0h, 0E0h, 080h

; whole name table: spaces, keyboard, octave numbers, help
DRAWSTATIC:
        LD      HL, VNAM
        CALL    VWADDR
        LD      BC, 768
DRST1:  XOR     A
        OUT     (VDPD), A
        DEC     BC
        LD      A, B
        OR      C
        JR      NZ, DRST1
        LD      HL, VNAM + 21 * 32
        CALL    VWADDR
        LD      B, 32
        LD      C, 0
DRST2:  LD      A, C
        ADD     A, PKEY
        OUT     (VDPD), A
        INC     C
        LD      A, C
        CP      3
        JR      C, DRST3
        LD      C, 0
DRST3:  DJNZ    DRST2
        LD      HL, OCTROW
        LD      DE, VNAM + 22 * 32
        CALL    PRINT
        LD      HL, HELPROW
        LD      DE, VNAM + 23 * 32
        CALL    PRINT
        LD      HL, DIRTY
        LD      B, NSLOT
DRST4:  LD      (HL), 3
        INC     HL
        DJNZ    DRST4
        LD      A, 1
        LD      (STDIRTY), A
        RET

;         0123456789012345678901234567890 1
OCTROW: DB      "   0  1  2  3  4  5  6  7  8  9", 0
HELPROW:
        DB      "F1-4 MODE F5 MAP R/S ROM/SF ESC", 0

; string HL (0-terminated) at VRAM DE
PRINT:  DI
        EX      DE, HL
        CALL    VWADDR
        EX      DE, HL
PRINT1: LD      A, (HL)
        OR      A
        JR      Z, PRINT2
        SUB     32
        OUT     (VDPD), A
        INC     HL
        JR      PRINT1
PRINT2: EI
        RET

; ------------------------------------------------------------------------- redraw
REDRAW: LD      A, (STDIRTY)
        OR      A
        CALL    NZ, DRAWSTAT
        LD      C, 0
REDR1:  LD      HL, DIRTY
        CALL    SLOTHL
        LD      A, (HL)
        LD      (HL), 0
        PUSH    AF
        RRCA
        PUSH    BC
        CALL    C, DRAWLANE
        POP     BC
        POP     AF
        AND     2
        PUSH    BC
        CALL    NZ, DRAWTEXT
        POP     BC
        INC     C
        LD      A, C
        CP      NSLOT
        JR      C, REDR1
        RET

; lane of slot C (row 4 + 2C)
DRAWLANE:
        LD      A, C
        ADD     A, A
        ADD     A, 4
        CALL    ROWADDR
        DI
        CALL    VWADDR
        LD      A, C
        ADD     A, A
        ADD     A, A
        ADD     A, A
        ADD     A, A
        LD      L, A
        LD      H, NOTES / 256
        ADD     A, PROLL
        LD      E, A                    ; first pattern of the slot
        LD      B, 16
DRLN1:  LD      A, (HL)
        AND     0Fh
        ADD     A, E
        OUT     (VDPD), A
        LD      A, (HL)
        RRCA
        RRCA
        RRCA
        RRCA
        AND     0Fh
        ADD     A, E
        OUT     (VDPD), A
        INC     HL
        DJNZ    DRLN1
        EI
        RET

; A = row -> HL = name table address
ROWADDR:
        LD      L, A
        LD      H, 0
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        LD      DE, VNAM
        ADD     HL, DE
        RET

; text row of slot C (row 3 + 2C): block, channel, name, note, velocity
DRAWTEXT:
        CALL    LINECLR
        LD      A, C
        ADD     A, PLEG
        LD      (LINE), A
        LD      A, C
        ADD     A, 2
        LD      DE, LINE + 1
        CALL    DEC2
        ; name
        PUSH    BC
        LD      A, C
        CP      8
        JR      Z, DRTXD
        LD      HL, PROG
        CALL    SLOTHL
        LD      L, (HL)
        LD      H, 0
        LD      DE, NAMES_MT
        LD      A, (MAP)
        OR      A
        JR      Z, DRTX1
        LD      DE, NAMES_GM
        JR      DRTX1
DRTXD:  LD      HL, LNOTE + 8           ; rhythm: name of the last key
        LD      A, (MODE)
        CP      2
        JR      NZ, DRTXD1
        LD      HL, DRUMKEY
DRTXD1: LD      A, (HL)
        SUB     35
        CP      47
        LD      DE, RHYTHM
        JR      NC, DRTX2
        LD      L, A
        LD      H, 0
        LD      DE, DRUM_MT
        LD      A, (MAP)
        OR      A
        JR      Z, DRTX1
        LD      DE, DRUM_GM
DRTX1:  ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, HL
        ADD     HL, DE
        EX      DE, HL
DRTX2:  EX      DE, HL                  ; HL = 16 characters
        LD      DE, LINE + 4
        LD      B, 16
DRTX3:  LD      A, (HL)
        SUB     32
        LD      (DE), A
        INC     HL
        INC     DE
        DJNZ    DRTX3
        POP     BC
        ; note and velocity
        LD      HL, LNOTE
        CALL    SLOTHL
        LD      A, (HL)
        CP      0FFh
        JR      Z, DRTX5
        LD      DE, LINE + 21
        CALL    NOTENAME
        LD      HL, LVEL
        CALL    SLOTHL
        LD      A, (HL)
        LD      DE, LINE + 26
        CALL    DEC3
DRTX5:  LD      A, C
        ADD     A, A
        ADD     A, 3
        ; fall through
; LINE -> row A
LINEOUT:
        PUSH    BC
        CALL    ROWADDR
        DI
        CALL    VWADDR
        LD      HL, LINE
        LD      B, 32
LOUT1:  LD      A, (HL)
        OUT     (VDPD), A
        INC     HL
        DJNZ    LOUT1
        EI
        POP     BC
        RET

RHYTHM: DB      "Rhythm          "

LINECLR:
        LD      HL, LINE
        LD      B, 32
LCLR1:  LD      (HL), 0
        INC     HL
        DJNZ    LCLR1
        RET

; string HL (0-terminated) into LINE at DE
LINESTR:
        LD      A, (HL)
        OR      A
        RET     Z
        SUB     32
        LD      (DE), A
        INC     HL
        INC     DE
        JR      LINESTR

; A -> 2 / 3 decimal digits at DE (patterns), DE advanced
DEC3:   LD      B, 100
        CALL    DECDIG
DEC2:   LD      B, 10
        CALL    DECDIG
        ADD     A, P0
        LD      (DE), A
        INC     DE
        RET
DECDIG: LD      H, P0
DECD1:  CP      B
        JR      C, DECD2
        SUB     B
        INC     H
        JR      DECD1
DECD2:  LD      L, A
        LD      A, H
        LD      (DE), A
        INC     DE
        LD      A, L
        RET

; note A -> "C#4" / "C4" / "C-1" at DE
NOTENAME:
        LD      B, -1
NOTEN1: INC     B
        SUB     12
        JR      NC, NOTEN1
        ADD     A, 12                   ; A = pitch class, B = octave + 1
        PUSH    BC
        ADD     A, A
        LD      HL, NOTETAB
        ADD     A, L
        LD      L, A
        JR      NC, NOTEN2
        INC     H
NOTEN2: LD      A, (HL)
        SUB     32
        LD      (DE), A
        INC     DE
        INC     HL
        LD      A, (HL)
        SUB     32
        JR      Z, NOTEN4               ; "C " -> "C4"
        LD      (DE), A
        INC     DE
NOTEN4: POP     BC
        LD      A, B
        OR      A
        JR      NZ, NOTEN3
        LD      A, PDASH
        LD      (DE), A
        INC     DE
        LD      A, P1
        LD      (DE), A
        RET
NOTEN3: DEC     A
        ADD     A, P0
        LD      (DE), A
        RET
NOTETAB:
        DB      "C C#D D#E F F#G G#A A#B "

; title, status and hint rows
DRAWSTAT:
        XOR     A
        LD      (STDIRTY), A
        ; row 0: title, map, ROM set, SoundFont
        CALL    LINECLR
        LD      HL, TITLE
        LD      A, (MIDIOK)
        OR      A
        JR      NZ, DRST0
        LD      HL, NOMIDI
DRST0:  LD      DE, LINE
        CALL    LINESTR
        LD      HL, TXMT
        LD      A, (MAP)
        OR      A
        JR      Z, DRSTM
        LD      HL, TXGM
DRSTM:  LD      DE, LINE + 14
        CALL    LINESTR
        LD      A, (ROMSET)
        LD      DE, LINE + 25
        CALL    DIGFF
        LD      A, (SFONT)
        LD      DE, LINE + 31
        CALL    DIGFF
        XOR     A
        CALL    LINEOUT
        ; row 1: mode and its values
        CALL    LINECLR
        LD      A, (MODE)
        ADD     A, A
        LD      L, A
        LD      H, 0
        LD      DE, MODETX
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        LD      DE, LINE
        CALL    LINESTR
        LD      A, (MODE)
        OR      A
        JR      NZ, DRSV1
        LD      A, (SPEED)
        LD      DE, LINE + 17
        CALL    DEC2
        JR      DRSV4
DRSV1:  DEC     A
        JR      NZ, DRSV2
        LD      A, (INSTPRG)
        LD      DE, LINE + 17
        CALL    DEC3
        JR      DRSV4
DRSV2:  DEC     A
        JR      NZ, DRSV3
        LD      A, (DRUMKEY)
        LD      DE, LINE + 17
        CALL    DEC3
        JR      DRSV4
DRSV3:  LD      A, (OCTAVE)
        LD      DE, LINE + 12
        ADD     A, P0
        LD      (DE), A
        LD      A, (KEYPRG)
        LD      DE, LINE + 18
        CALL    DEC3
DRSV4:  LD      A, (PAUSED)
        OR      A
        JR      Z, DRSV5
        LD      HL, TXPAUSE
        LD      DE, LINE + 25
        CALL    LINESTR
DRSV5:  LD      A, (RESEND)
        OR      A
        JR      Z, DRSV6
        LD      HL, TXWAIT
        LD      DE, LINE + 25
        CALL    LINESTR
DRSV6:  LD      A, 1
        CALL    LINEOUT
        ; row 2: keys of the mode
        CALL    LINECLR
        LD      A, (MODE)
        ADD     A, A
        LD      L, A
        LD      H, 0
        LD      DE, HINTTX
        ADD     HL, DE
        LD      E, (HL)
        INC     HL
        LD      D, (HL)
        EX      DE, HL
        LD      DE, LINE
        CALL    LINESTR
        LD      A, 2
        JP      LINEOUT

; A = 0-9 or FFh ("-") at DE
DIGFF:  CP      0FFh
        LD      B, PDASH
        JR      Z, DIGF1
        ADD     A, P0
        LD      B, A
DIGF1:  LD      A, B
        LD      (DE), A
        RET

;               0123456789012345678901234567890 1
TITLE:  DB      "MSX-MIDI TEST", 0
NOMIDI: DB      "NO MIDI AT E8H", 0
TXMT:   DB      "MT-32  ROM -  SF -", 0
TXGM:   DB      "GM     ROM -  SF -", 0
TXPAUSE:
        DB      "PAUSED", 0
TXWAIT: DB      "WAIT", 0
MODETX: DW      MT0, MT1, MT2, MT3
MT0:    DB      "F1 SONG    SPEED", 0
MT1:    DB      "F2 INSTRUMENT", 0
MT2:    DB      "F3 DRUM KEY", 0
MT3:    DB      "F4 KEYS OCT   PRG", 0
HINTTX: DW      HT0, HT1, HT2, HT3
HT0:    DB      "UP/DN SPEED  SPACE PAUSE", 0
HT1:    DB      "L/R PROGRAM  SPACE PAUSE", 0
HT2:    DB      "L/R KEY  SPACE PAUSE", 0
HT3:    DB      "Z..M Q..I PLAY L/R OCT UP/DN PRG", 0

        INCLUDE "data.inc"

ROMEND:
        DS      8000h - ROMEND, 0FFh    ; fails above 16 kB
