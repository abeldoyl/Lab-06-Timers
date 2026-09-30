    ; Abel Doyle
    ; RCET3375
    ; Lab6-1Timers
    ; https://github.com/abeldoyl/Lab-06-Timers/tree/main/Lab6-1Timers.X
    
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
 TMR1_PRELOAD_HI EQU 0xB1  ; 65536 - 20000 = 45536 = 0xB1E0 -> exact 20,000 Tcy period
  TMR1_PRELOAD_LO EQU 0xE0
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
 
    CLRF T1CON      ;TMR1CS=0 (Fosc/4), prescale 1:1, TMR1ON=0 (off until preload is loaded)
    MOVLW TMR1_PRELOAD_HI
    MOVWF TMR1H     ;Load Timer1 preload, high byte
    MOVLW TMR1_PRELOAD_LO
    MOVWF TMR1L     ;Load Timer1 preload, low byte
    BCF PIR1,0      ;Clear TMR1IF before enabling
 
    ; Bank 1
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;"
    CLRF TRISA      ;Making PORTA an output (RA0 = timer pulse, RA1 = main-loop toggle)
    CLRF TRISC      ;Making PORTC an output
    BSF PIE1,0      ;Enables the TMR1 interrupt bit (PIE1<TMR1IE>)
 
    ; Bank 3
    BSF 0x03,6      ;Set Bank 3
    BSF 0x03,5      ;"
    CLRF ANSEL      ;Making PORTA digital I/O
    CLRF ANSELH     ;Making PORTB digital I/O
 
    ;Interrupts
    BCF 0x03,6      ;Set Bank 1
    BSF 0x03,5      ;"
    BSF INTCON,6    ;Enables peripheral interrupts (PEIE, required for TMR1)
    BSF INTCON,7    ;Enables global interrupts
 
    BCF 0x03,6      ;Set Bank 0
    BCF 0x03,5      ;"
    BSF T1CON,0     ;TMR1ON=1, starts Timer1 - period boundary begins here
    goto Main
 
Main:
    ; main code goes here
    MOVLW 0x02      ;1 TCY   (bit 1 = RA1, main-loop diagnostic)
    XORWF PORTA,1   ;1 TCY
    goto Main
 
ISRHandler:
    MOVWF W_TEMP ;Copy W to TEMP register
    SWAPF STATUS,W ;Swap status to be saved into W
    ;Swaps are used because they do not affect the status bits
    MOVWF STATUS_TEMP ;Save status to bank zero STATUS_TEMP register
    ;No bank-forcing needed here: Main never leaves Bank 0 (it only
    ;touches PORTA), so the CPU is guaranteed to already be in Bank 0
    ;when the interrupt is taken. TMR1H/TMR1L/PIR1/T1CON/PORTA are
    ;all Bank 0 registers.
 
    ;--- Step 1: service the timer ---
    MOVLW TMR1_PRELOAD_HI
    MOVWF TMR1H     ;Reload Timer1 high byte
    MOVLW TMR1_PRELOAD_LO
    MOVWF TMR1L     ;Reload Timer1 low byte
    BCF PIR1,0      ;Clears TMR1IF
 
    ;--- Steps 2/3: diagnostic pulse, adjacent instructions ---
    BSF PORTA,0     ;Timer diagnostic pulse HIGH (RA0)
    BCF PORTA,0     ;Timer diagnostic pulse LOW, immediately following
    goto LeaveISR
 
LeaveISR:
    SWAPF STATUS_TEMP,W ;Swap STATUS_TEMP register into W
    ;(sets bank to original state)
    MOVWF STATUS ;Move W into STATUS register
    SWAPF W_TEMP,F ;Swap W_TEMP
    SWAPF W_TEMP,W ;Swap W_TEMP into W
    RETFIE
 
End