    ; Abel Doyle
    ; RCET3375
    ; Lab6-3Timers
    ; https://github.com/abeldoyl/Lab-06-Timers/tree/main/Lab6-3Timers.X
    
; PIC16F883 Configuration Bit Settings

; Assembly source line config statements

; CONFIG1
  CONFIG  FOSC = XT             ; Oscillator Selection bits (XT oscillator: Crystal/resonator on RA6/OSC2/CLKOUT and RA7/OSC1/CLKIN)
  CONFIG  WDTE = OFF            ; Watchdog Timer Enable bit (WDT disabled and can be enabled by SWDTEN bit of the WDTCON register)
  CONFIG  PWRTE = OFF           ; Power-up Timer Enable bit (PWRT disabled)
  CONFIG  MCLRE = ON            ; RE3/MCLR pin function select bit (RE3/MCLR pin function is MCLR)
  CONFIG  CP = OFF              ; Code Protection bit (Program memory code protection is disabled)
  CONFIG  CPD = OFF             ; Data Code Protection bit (Data memory code protection is disabled)
  CONFIG  BOREN = OFF           ; Brown Out Reset Selection bits (BOR disabled)
  CONFIG  IESO = OFF            ; Internal External Switchover bit (Internal/External Switchover mode is disabled)
  CONFIG  FCMEN = OFF           ; Fail-Safe Clock Monitor Enabled bit (Fail-Safe Clock Monitor is disabled)
  CONFIG  LVP = OFF             ; Low Voltage Programming Enable bit (RB3 pin has digital I/O, HV on MCLR must be used for programming)

; CONFIG2
  CONFIG  BOR4V = BOR40V        ; Brown-out Reset Selection bit (Brown-out Reset set to 4.0V)
  CONFIG  WRT = OFF             ; Flash Program Memory Self Write Enable bits (Write protection off)

; config statements should precede project file includes.
#include <xc.inc>
  W_TEMP EQU 0x70
  STATUS_TEMP EQU 0x71
  ; intersection_state: [7:4]=STATE_COUNT  [3]=TRANS  [2]=EW_DETECTED
  ;                     [1]=NS_DETECTED    [0]=DIR
  intersection_state EQU 0x20
  temp EQU 0x21           ; scratch

  ; Timer1 reload: 65536 - 62500 = 3036 = 0x0BDC (0.5 s @ 4 MHz, 1:8)
  T1_RELOAD_H EQU 0x0B
  T1_RELOAD_L EQU 0xDC
  COUNT_END_GREEN  EQU 0x0A   ; 5.0 s of green
  COUNT_END_YELLOW EQU 0x02   ; 1.0 s of yellow (count restarts at 0 for yellow)

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
    MOVLW 0x07
    MOVWF TRISB             ; PORTB unused in Part 3 (left as inputs)

    ; Bank 3
    BSF 0x03,6
    BSF 0x03,5
    CLRF ANSEL
    CLRF ANSELH

    ; Timer1 setup (Bank 0)
    BCF 0x03,6
    BCF 0x03,5
    MOVLW 0x30              ; 1:8 prescaler, internal clock, timer OFF
    MOVWF T1CON
    MOVLW T1_RELOAD_H
    MOVWF TMR1H
    MOVLW T1_RELOAD_L
    MOVWF TMR1L
    BCF PIR1,0              ; clear stale TMR1IF

    ; Bank 1: enable Timer1 interrupt
    BCF 0x03,6
    BSF 0x03,5
    BSF PIE1,0              ; TMR1IE

    ; Bank 0
    BCF 0x03,6
    BCF 0x03,5
    BSF INTCON,6            ; PEIE (needed for peripheral interrupts)
    BSF T1CON,0             ; start Timer1
    BSF INTCON,7            ; GIE

    goto Main

Main:
    ;1) Display the packed state on PORTC every pass
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

    ;3) Critical section: block ISR while reading/modifying the state byte
    BCF INTCON,7
    BTFSC INTCON,7          ; confirm GIE really cleared
    goto $-2

    SWAPF intersection_state,W
    ANDLW 0x0F
    MOVWF temp              ; temp = STATE_COUNT

    MOVLW COUNT_END_GREEN
    XORWF temp,W
    BTFSC 0x03,2
    goto CountA

    MOVLW COUNT_END_YELLOW
    XORWF temp,W
    BTFSC 0x03,2
    goto CountC

    goto EvalDone           ; all other counts: do nothing

CountA:                     ; 5.0 s: green over, begin yellow
    MOVLW 0x07              ; keep DIR, NS_DETECTED, EW_DETECTED
    ANDWF intersection_state,F  ; clears STATE_COUNT and TRANS
    BSF intersection_state,3    ; set TRANSITION
    goto EvalDone

CountC:                     ; 6.0 s: finish an ACTIVE transition
    BTFSS intersection_state,3
    goto EvalDone
    MOVLW 0x01
    ANDWF intersection_state,W  ; keep DIR only (clears count, TRANS, flags)
    XORLW 0x01                  ; toggle direction
    MOVWF intersection_state

EvalDone:
    BSF INTCON,7
    goto Main

ISRHandler:
    MOVWF W_TEMP
    SWAPF STATUS,W
    MOVWF STATUS_TEMP

    BCF 0x03,6              ; force Bank 0
    BCF 0x03,5

    BTFSC PIR1,0            ; TMR1IF set?
    CALL Timer1_Service

LeaveISR:
    SWAPF STATUS_TEMP,W
    MOVWF STATUS
    SWAPF W_TEMP,F
    SWAPF W_TEMP,W
    RETFIE

; ----- Timer1 interrupt: reload, increment STATE_COUNT only -----
Timer1_Service:
    MOVLW T1_RELOAD_H       ; reload for the next 0.5 s period
    MOVWF TMR1H
    MOVLW T1_RELOAD_L
    MOVWF TMR1L

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
    BCF PIR1,0              ; clear TMR1IF
    RETURN

End