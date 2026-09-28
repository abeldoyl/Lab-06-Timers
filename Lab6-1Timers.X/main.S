    ; Abel Doyle
    ; RCET3373
    ; Lab5-1ISR
    ; https://github.com/abeldoyl/Lab-05-ISRs/tree/main/Lab5-1ISR.X
    
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
    ; add device setup here
    ; Bank 0
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    CLRF PORTA      ;Clearing PORTA on reset
    CLRF PORTB      ;Clearing PORTB on reset
    CLRF PORTC	    ;Clearing PORTC on reset
 
    ; Bank 1
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;"
    CLRF TRISA      ;Making PORTA an output
    CLRF TRISC	    ;Making PORTC an output
 
    ; Bank 3
    BSF 0x03,6      ;Set Bank 3
    BSF 0x03,5      ;"
    CLRF ANSEL      ;Making PORTA digital I/O
    CLRF ANSELH     ;Making PORTB digital I/O
 
    ;Interrupts
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5	    ;"
    BCF OPTION_REG,6;Allows for interrupt on falling edge
    BCF INTCON,1
    BSF INTCON,4    ;Enables the INT external Interrupt bit
    BSF INTCON,7    ;Enables global interrupts
    
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    goto Main
    
Main:
    ; main code goes here
    MOVLW 0x01      ;1 TCY
    XORWF PORTA,1   ;1 TCY
    goto Main
    
ISRHandler:
    MOVWF W_TEMP ;Copy W to TEMP register
    SWAPF STATUS,W ;Swap status to be saved into W
    ;Swaps are used because they do not affect the status bits
    MOVWF STATUS_TEMP ;Save status to bank zero STATUS_TEMP register
    
    INCF PORTC	    ;Increments PORTC on every interrupt
    BCF INTCON,1    ;Clears the flag on RBo/INT
    goto LeaveISR
    
LeaveISR:
    SWAPF STATUS_TEMP,W ;Swap STATUS_TEMP register into W
    ;(sets bank to original state)
    MOVWF STATUS ;Move W into STATUS register
    SWAPF W_TEMP,F ;Swap W_TEMP
    SWAPF W_TEMP,W ;Swap W_TEMP into W
    RETFIE
  
End
    