    ; Abel Doyle
    ; RCET3375
    ; Lab6-4Timers
    ; https://github.com/abeldoyl/Lab-06-Timers/tree/main/Lab6-4Timers.X
    
; PIC16F883 Configuration Bit Settings
; CONFIG1
  CONFIG  FOSC = XT
  CONFIG  WDTE = OFF
  CONFIG  PWRTE = OFF
  CONFIG  MCLRE = ON
  CONFIG  CP = OFF
  CONFIG  CPD = OFF
  CONFIG  BOREN = OFF
  CONFIG  IESO = OFF
  CONFIG  FCMEN = OFF
  CONFIG  LVP = OFF
; CONFIG2
  CONFIG  BOR4V = BOR40V
  CONFIG  WRT = OFF
 
#include <xc.inc>
  W_TEMP EQU 0x70
  STATUS_TEMP EQU 0x71
  ; intersection_state: [7:4]=STATE_COUNT  [3]=TRANS  [2]=EW_DETECTED
  ;                     [1]=NS_DETECTED    [0]=DIR
  intersection_state EQU 0x20
  temp EQU 0x21           ; scratch
  portb_prev EQU 0x22     ; last PORTB sample (rising-edge detect)
  portb_cur EQU 0x23
  portb_rise EQU 0x24
  mode_sel EQU 0x25       ; bit0: requested mode from RB3 (1=RUN, 0=DEBUG) - written by ISR
  mode_hw EQU 0x26        ; bit0: mode currently applied   (1=RUN, 0=DEBUG) - written by main, GIE off
 
  ; Timer1 reload: 65536 - 62500 = 3036 = 0x0BDC (0.5 s @ 4 MHz, 1:8)
  T1_RELOAD_H EQU 0x0B
  T1_RELOAD_L EQU 0xDC
  COUNT_END_GREEN  EQU 0x0A   ; 5.0 s of green
  COUNT_END_YELLOW EQU 0x02   ; 1.0 s of yellow (count restarts at 0)
 
PSECT resetVect,class=CODE,delta=2
ResetVector:
    goto Setup
 
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler
 
PSECT code,class=CODE,delta=2
 
Setup:
    ; Bank 0
    BCF 0x03,6
    BCF 0x03,5
    CLRF PORTA
    CLRF PORTB
    CLRF PORTC
    CLRF intersection_state
 
    ; Bank 1
    BCF 0x03,6
    BSF 0x03,5
    CLRF TRISA              ; PORTA = traffic-light outputs
    CLRF TRISC              ; PORTC = state display
    MOVLW 0x0F
    MOVWF TRISB             ; RB0 INT, RB1 N/S, RB2 E/W, RB3 mode select
    BSF OPTION_REG,6        ; INTEDG: rising edge on RB0
 
    ; Bank 3
    BSF 0x03,6
    BSF 0x03,5
    CLRF ANSEL
    CLRF ANSELH
 
    ; Bank 0: Timer1 (stopped, 1:8, internal clock)
    BCF 0x03,6
    BCF 0x03,5
    MOVLW 0x30
    MOVWF T1CON
    BCF PIR1,0
 
    ; Baseline PORTB sample and mode request
    CLRF portb_cur
    CLRF portb_rise
    MOVF PORTB,W
    MOVWF portb_prev
    CLRF mode_sel
    BTFSS PORTB,3
    BSF mode_sel,0          ; RB3=0 -> RUN
    MOVF mode_sel,W
    XORLW 0x01
    MOVWF mode_hw           ; deliberately != mode_sel: forces ApplyMode on first pass
    BCF INTCON,1            ; clear stale INTF
    BCF INTCON,0            ; clear stale RBIF
 
    ; Bank 1: IOC on RB1, RB2, RB3. TMR1IE and INTE stay OFF until ApplyMode.
    BCF 0x03,6
    BSF 0x03,5
    BSF IOCB,1
    BSF IOCB,2
    BSF IOCB,3
    BCF PIE1,0
    BSF INTCON,3            ; RBIE
    BCF INTCON,4            ; INTE off
    BSF INTCON,6            ; PEIE
    BSF INTCON,7            ; GIE
 
    BCF 0x03,6
    BCF 0x03,5
    goto Main
 
Main:
    ;1) Display the packed state every pass
    MOVF intersection_state,W
    MOVWF PORTC
 
    ;2) Decode DIRECTION and TRANSITION into PORTA every pass
    BTFSC intersection_state,0
    goto EW_Dir
NS_Dir:
    BTFSC intersection_state,3
    goto NS_Yellow
    MOVLW 0x0C              ; N/S green, E/W red
    goto WritePortA
NS_Yellow:
    MOVLW 0x0A              ; N/S yellow, E/W red
    goto WritePortA
EW_Dir:
    BTFSC intersection_state,3
    goto EW_Yellow
    MOVLW 0x21              ; N/S red, E/W green
    goto WritePortA
EW_Yellow:
    MOVLW 0x11              ; N/S red, E/W yellow
WritePortA:
    MOVWF PORTA
 
    ;3) Critical section: block ISR while reading/modifying shared state
    BCF INTCON,7
    BTFSC INTCON,7          ; confirm GIE really cleared
    goto $-2
 
    ; apply a pending mode change (GIE is off)
    MOVF mode_sel,W
    XORWF mode_hw,W
    BTFSS 0x03,2            ; Z set -> same mode
    CALL ApplyMode
 
    ; extract STATE_COUNT into temp[3:0]
    SWAPF intersection_state,W
    ANDLW 0x0F
    MOVWF temp
 
    MOVLW COUNT_END_GREEN
    XORWF temp,W
    BTFSC 0x03,2
    goto CountA
 
    MOVLW COUNT_END_YELLOW
    XORWF temp,W
    BTFSC 0x03,2
    goto CountC
 
    goto EvalDone           ; all other counts: do nothing
 
CountA:                     ; 5.0 s: end of green -> Part 2 decision
    BTFSC intersection_state,3
    goto EvalDone           ; already transitioning
    BTFSC intersection_state,0
    goto EW_Green
    goto NS_Green
 
CountC:                     ; 1.0 s of yellow: finish an ACTIVE transition
    BTFSS intersection_state,3
    goto EvalDone
    MOVLW 0x01
    ANDWF intersection_state,W  ; keep DIR only (clears count, TRANS, flags)
    XORLW 0x01                  ; toggle direction
    MOVWF intersection_state
 
EvalDone:
    BSF INTCON,7
    goto Main
 
NS_Green:                   ; stay only if NS=1 and EW=0
    BTFSS intersection_state,1
    goto BeginTransition
    BTFSC intersection_state,2
    goto BeginTransition
    goto SameDirection
 
EW_Green:                   ; stay only if EW=1 and NS=0
    BTFSS intersection_state,2
    goto BeginTransition
    BTFSC intersection_state,1
    goto BeginTransition
    goto SameDirection
 
BeginTransition:            ; Part 3 style: restart count for 1 s yellow, set TRANS
    MOVLW 0x07              ; keep DIR, NS, EW; clear count and TRANS
    ANDWF intersection_state,F
    BSF intersection_state,3
    goto EvalDone
 
SameDirection:              ; clear count, NS, EW; keep DIR (and TRANS, which is 0)
    MOVLW 0x09
    ANDWF intersection_state,F
    goto EvalDone
 
; ----- ApplyMode: called with GIE = 0. Returns in Bank 0. -----
; Only the hardware advance source is changed; intersection_state is untouched.
ApplyMode:
    BTFSS mode_sel,0
    goto ToDebug
 
ToRun:                      ; INT off, Timer on
    BCF INTCON,4            ; INTE off
    BCF INTCON,1            ; clear stale INTF
    BCF T1CON,0             ; make sure Timer1 stopped while reloading
    MOVLW T1_RELOAD_H
    MOVWF TMR1H
    MOVLW T1_RELOAD_L
    MOVWF TMR1L
    BCF PIR1,0              ; clear stale TMR1IF
    BCF 0x03,6
    BSF 0x03,5              ; Bank 1
    BSF PIE1,0              ; TMR1IE on
    BCF 0x03,5              ; Bank 0
    BSF T1CON,0             ; start Timer1
    MOVLW 0x01
    MOVWF mode_hw
    RETURN
 
ToDebug:                    ; Timer off, INT on
    BCF T1CON,0             ; stop Timer1
    BCF 0x03,6
    BSF 0x03,5              ; Bank 1
    BCF PIE1,0              ; TMR1IE off
    BCF 0x03,5              ; Bank 0
    BCF PIR1,0              ; clear stale TMR1IF
    BCF INTCON,1            ; clear stale INTF BEFORE enabling INTE
    BSF INTCON,4            ; INTE on
    CLRF mode_hw
    RETURN
 
ISRHandler:
    MOVWF W_TEMP
    SWAPF STATUS,W
    MOVWF STATUS_TEMP
 
    BCF 0x03,6              ; force Bank 0
    BCF 0x03,5
 
    BTFSC INTCON,1          ; INTF set?
    CALL INT_Service
    BTFSC INTCON,0          ; RBIF set?
    CALL IOC_Service
    BTFSC PIR1,0            ; TMR1IF set?
    CALL Timer1_Service
 
LeaveISR:
    SWAPF STATUS_TEMP,W
    MOVWF STATUS
    SWAPF W_TEMP,F
    SWAPF W_TEMP,W
    RETFIE
 
; ----- INT: always clear flag; advance count only in DEBUG -----
INT_Service:
    BCF INTCON,1
    BTFSC mode_hw,0         ; RUN -> ignore
    RETURN
    goto Increment_Count
 
; ----- Timer1: always clear flag; reload + advance only in RUN -----
Timer1_Service:
    BCF PIR1,0
    BTFSS mode_hw,0         ; DEBUG -> ignore
    RETURN
    MOVLW T1_RELOAD_H
    MOVWF TMR1H
    MOVLW T1_RELOAD_L
    MOVWF TMR1L
    goto Increment_Count
 
; ----- Shared increment: STATE_COUNT only (called by both sources) -----
Increment_Count:
    MOVF intersection_state,W
    ANDLW 0xF0              ; extract count, flags masked off
    MOVWF temp
    SWAPF temp,F            ; count into bits 3:0
    INCF temp,F
    MOVLW 0x0F
    ANDWF temp,F            ; wrap 15->0
    SWAPF temp,F            ; back to bits 7:4
    MOVLW 0x0F
    ANDWF intersection_state,F  ; keep flags, zero old count
    MOVF temp,W
    IORWF intersection_state,F  ; merge new count with preserved flags
    RETURN
 
; ----- PORTB IOC: car events on RB1/RB2, mode request from RB3 -----
IOC_Service:
    MOVF PORTB,W            ; reading PORTB ends the mismatch condition
    MOVWF portb_cur
    XORWF portb_prev,W      ; W = bits that changed
    ANDWF portb_cur,W       ; W = changed AND now high = rising edges
    MOVWF portb_rise
    MOVF portb_cur,W
    MOVWF portb_prev
 
    BTFSC portb_rise,1      ; RB1 rose -> N/S car
    BSF intersection_state,1
    BTFSC portb_rise,2      ; RB2 rose -> E/W car
    BSF intersection_state,2
 
    CLRF mode_sel           ; RB3 level = requested mode (not a car sensor)
    BTFSS portb_cur,3
    BSF mode_sel,0	    ; RB3 low -> RUN
 
    BCF INTCON,0            ; clear RBIF (after the PORTB read)
    RETURN
 
End
 