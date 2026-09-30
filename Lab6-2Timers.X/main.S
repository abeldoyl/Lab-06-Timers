    ; Abel Doyle
    ; RCET3375
    ; Lab6-2Timers
    ; https://github.com/abeldoyl/Lab-06-Timers/tree/main/Lab6-2Timers.X
    
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
  intersection_state EQU 0x20
  temp EQU 0x21   ; scratch
  portb_prev EQU 0x22   ; last PORTB sample (for rising-edge detect)
  portb_cur EQU 0x23
  portb_rise EQU 0x24
; Reset Vector at 0000h. Execution starts here after reset.
PSECT resetVect,class=CODE,delta=2
ResetVector: 
    goto Setup

; Interrupt Vector at 0004h. Execution starts here after an interrupt.
PSECT isrVect,class=CODE,delta=2
InterruptVector:
    goto ISRHandler

; Main code section starts at 0008h. User code goes here.
PSECT code,class=CODE,delta=2
 
Setup:
   ; Bank 0
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    CLRF PORTA      ;Clearing PORTA on reset
    CLRF PORTB      ;Clearing PORTB on reset
    CLRF PORTC      ;Clearing PORTC on reset
    CLRF intersection_state
 
    ; Bank 1
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;"
    CLRF TRISA      ;Making PORTA an output
    CLRF TRISC      ;Making PORTC an output
    MOVLW 0x07
    MOVWF TRISB     ; RB0 = advance (INT), RB1 = N/S car, RB2 = E/W car
    BSF OPTION_REG,6 ; INTEDG: rising edge on RB0
 
    ; Bank 3
    BSF 0x03,6      ;Set Bank 3
    BSF 0x03,5      ;"
    CLRF ANSEL      ;Making PORTA digital I/O
    CLRF ANSELH     ;Making PORTB digital I/O
 
    ;Interrupts
    BCF 0x03,6      ;Set Bank 0 (INTCON is reachable from any bank)
    BCF 0x03,5
    CLRF portb_cur      ; start from known values
    CLRF portb_rise
    MOVF PORTB,W        ; baseline sample of the pins
    MOVWF portb_prev
    BCF INTCON,1        ; clear stale INTF (after the read)
    BCF INTCON,0        ; clear stale RBIF (after the read)
    
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;"
    BSF IOCB,1	    ;Enable interrupt-on-change for PORTB bit 1
    BSF IOCB,2
    BSF INTCON,3
    BSF INTCON,4
    BSF INTCON,7    ;Enables global interrupts
 
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    goto Main
 
Main:
    ; main code goes here
    ;1) Display the packed state on every pass
    MOVF intersection_state,W
    MOVWF PORTC
    
    ;2) Critical section: block ISRs while we read/modify the state byte
    BCF INTCON,7
    BTFSC INTCON,7  ;confirm GIE really cleared
    goto $-2
 
    ;extract STATE_COUNT into temp[3:0]
    SWAPF intersection_state,W
    ANDLW 0x0F
    MOVWF temp
 
    MOVLW 0x03
    XORWF temp,W
    BTFSC 0x03,2
    goto Count3
 
    MOVLW 0x04
    XORWF temp,W
    BTFSC 0x03,2
    goto Count4
 
    goto EvalDone		;counts 0,1,2 and 5-15: do nothing
    
Count3:
    BTFSC intersection_state,3
    goto EvalDone
    BTFSC intersection_state,0
    goto EW_Green
    goto NS_Green
    
Count4:
    BTFSS intersection_state,3
    goto EvalDone		;only finish an ACTIVE transition
    MOVLW 0x01
    ANDWF intersection_state,W  ;W = DIR only (everything else cleared)
    XORLW 0x01                  ;toggle Direction
    MOVWF intersection_state
 
EvalDone:
    BSF INTCON,7
    goto Main
    
NS_Green:			;stay only if NS=1 and EW=0
    BTFSS intersection_state,1
    goto BeginTransition
    BTFSC intersection_state,2
    goto BeginTransition
    goto SameDirection
 
EW_Green:			;stay only if EW=1 and NS=0
    BTFSS intersection_state,2
    goto BeginTransition
    BTFSC intersection_state,1
    goto BeginTransition
    goto SameDirection
    
BeginTransition:
    BSF intersection_state,3
    goto EvalDone
 
SameDirection:              ; clear count, NS, EW; keep DIR (and TRANS, which is 0)
    MOVLW 0x09              ; 0b00001001 = keep TRANS and DIR
    ANDWF intersection_state,F
    goto EvalDone
    
    
ISRHandler:
    MOVWF W_TEMP ;Copy W to TEMP register
    SWAPF STATUS,W ;Swap status to be saved into W
    ;Swaps are used because they do not affect the status bits
    MOVWF STATUS_TEMP ;Save status to bank zero STATUS_TEMP register
    
    BCF 0x03,6            ; force Bank 0 (ISR can fire in any bank)
    BCF 0x03,5
 
    BTFSC INTCON,1          ; INTF set?
    CALL INT_Service
    BTFSC INTCON,0          ; RBIF set?
    CALL IOC_Service
 
LeaveISR:
    SWAPF STATUS_TEMP,W ;Swap STATUS_TEMP register into W
    ;(sets bank to original state)
    MOVWF STATUS ;Move W into STATUS register
    SWAPF W_TEMP,F ;Swap W_TEMP
    SWAPF W_TEMP,W ;Swap W_TEMP into W
    RETFIE
    
; ----- External interrupt: increment STATE_COUNT only -----    
INT_Service:
    MOVF intersection_state,W
    ANDLW 0xF0              ; (1) extract count, flags masked off
    MOVWF temp
    SWAPF temp,F            ; (2) position count into bits 3:0
    INCF temp,F             ; (3) increment
    MOVLW 0x0F
    ANDWF temp,F            ;     wrap 15->0, nothing spills upward
    SWAPF temp,F            ; (4) back into bits 7:4, low nibble = 0
    MOVLW 0x0F
    ANDWF intersection_state,F  ; (5) keep flags, zero old count
    MOVF temp,W
    IORWF intersection_state,F  ;     merge new count with preserved flags
    BCF INTCON,1            ; clear INTF
    RETURN
 
; ----- PORTB IOC: latch low-to-high events on RB1 / RB2 -----
IOC_Service:
    MOVF PORTB,W            ; reading PORTB ends the mismatch condition
    MOVWF portb_cur
    XORWF portb_prev,W      ; W = bits that changed
    ANDWF portb_cur,W       ; W = changed AND now high = rising edges
    MOVWF portb_rise
    MOVF portb_cur,W
    MOVWF portb_prev        ; save sample for next time
 
    BTFSC portb_rise,1      ; RB1 rose -> N/S car
    BSF intersection_state,1
    BTFSC portb_rise,2      ; RB2 rose -> E/W car
    BSF intersection_state,2
 
    BCF INTCON,0            ; clear RBIF (after the PORTB read)
    RETURN
 
End