;      __CONFIG _FOSC_INTOSC & _BOREN_ON & _WDTE_OFF & _PWRTE_ON & _MCLRE_OFF & _CP_OFF & _LVP_OFF & _LPBOR_ON & _BORV_HI & _WRT_OFF
      __CONFIG _FOSC_INTOSC & _BOREN_ON & _WDTE_OFF & _PWRTE_OFF & _MCLRE_OFF & _CP_OFF & _LVP_OFF & _LPBOR_ON & _BORV_HI & _WRT_OFF
#include "p10f322.inc"
     
;====================================================================
; Variables & Constants
;====================================================================
PWMIN	    equ RA0 ; Port PWM
ZC	    equ RA1 ; Port Zero Cross
OUT	    equ RA2 ; Port MOC
FULL	    equ 0x01; ON/OFF TRIAC
I	    equ 0x02; INT ENABLE

	    constant Period = 0xFD ; impulse width
	    constant C.input_mask = (1<<PWMIN)
	    constant mindim = 0x80 
	    constant onfire = 0x03
	    constant PWMperiod = 0x50 ;0x64 ;(383 Hz)
	    constant FULLcount = 0x09 

           udata
W_TEMP		    res 1
STATUS_TEMP	    res 1
PR2_TMP		    res 1
count		    res 1
TMP		    res 1
FIRE		    res 1    
inputs.this_time    res 1	    
inputs.last_time    res 1
edgeR.detected	    res 1
edgeF.detected	    res 1	    

;====================================================================
; RESET and INTERRUPT VECTORS
;====================================================================
	ORG	0x00		; RESET VECTOR
	GOTO	START
	
	ORG	0x04		; INTERRUPT VECTOR
	MOVWF	W_TEMP		;Copy W to TEMP register
	SWAPF	STATUS,W	;Swap status to be saved into W
				;Swaps are used because they do 
				;not affect the status bits
	MOVWF	STATUS_TEMP	;Save status to bank zero STATUS_TEMP register
	BSF	FIRE,I
	BTFSC	INTCON,TMR0IF	; INTERRUPT TMR0
	GOTO	TRIAC.OFF
	BTFSC	PIR1,TMR2IF	; INTERRUPT TMR2
	GOTO	INTTMR2
	BTFSC	INTCON,IOCIF	; INTERRUPT-ON-CHANGE
	GOTO	SIN.START
	GOTO	ENDOFINT
	
TRIAC.OFF
	BTFSS	FIRE,FULL
	BCF	LATA,OUT	
	BCF	INTCON,TMR0IF
	BCF	INTCON, TMR0IE
	BCF	T2CON,TMR2ON
	BCF	PIR1, TMR2IF
	CLRF	TMR2
	MOVFW	PR2_TMP
	BCF	STATUS,Z
	BCF	STATUS,C
	SUBWF	PR2,W
	BTFSC	STATUS,Z
	INCF	PR2,F
	BTFSC	STATUS,C
	DECF	PR2,F
	BTFSS	STATUS,C
	INCF	PR2,F	
	GOTO	ENDOFINT	

SIN.START
	BTFSS	IOCAF, ZC	;INTERRUPT-ON-CHANGE PORTA 
	GOTO	ENDOFINT
	MOVLW   (1 << ZC)
	XORWF	IOCAF, W
	ANDWF	IOCAF, F
	BTFSC	PORTA, ZC
	GOTO	ENDOFINT	
	BSF	T2CON,TMR2ON
	;MOVLW	Period
	;MOVWF	TMR0
	;BCF	INTCON, TMR0IF
	;BSF	INTCON, TMR0IE
	GOTO	ENDOFINT
INTTMR2
	BSF	LATA,OUT
	BCF	T2CON,TMR2ON
	BCF	PIR1, TMR2IF
	MOVLW	Period
	MOVWF	TMR0
	BCF	INTCON, TMR0IF
	BSF	INTCON, TMR0IE	

ENDOFINT
	SWAPF	STATUS_TEMP,W	;Swap STATUS_TEMP register into W
				;(sets bank to original state)
	MOVWF	STATUS		;Move W into STATUS register
	SWAPF	W_TEMP,F	;Swap W_TEMP
	SWAPF	W_TEMP,W	;Swap W_TEMP into W
	retfie
      
;====================================================================
; CODE SEGMENT
;====================================================================

START
; OSC 4MHz (default 8MHz)
    CLRF	TMP     
    MOVLW	b'00100000'
    MOVWF	TMP
    MOVLW	b'01110000'
    IORWF	OSCCON,W
    XORWF	TMP,W
    MOVWF	OSCCON
    
; INIT PORTA
    CLRF	PORTA 
    CLRF        LATA 
    CLRF	ANSELA ;Ports all digital
    
; After reset all ports as input
    bsf		TRISA,ZC ; Input port Zero Cross
    bsf		TRISA,PWMIN ; Input port PWM
    BCF		TRISA,OUT    
    ;BSF		WPUA,PWMIN

; TMR0 INIT    
    MOVLW	b'10000101' ;1:64 tmr0 prescaler, pullups disable   
    MOVWF	OPTION_REG
   
; TMR2 INIT
    MOVLW	b'00000011' ;1:64 tmr2 prescaler, 1:1 postscaler, tmr2 off
    MOVWF	T2CON
    MOVLW	mindim
    MOVWF	PR2
    BSF		PIE1,TMR2IE ; Interrup TMR2 Enable

; NCO INIT 
    MOVLW	b'00000001'   
    MOVWF	NCO1CLK
    CLRF	NCO1CON
    CLRF	NCO1ACCL
    CLRF	NCO1ACCH
    CLRF	NCO1ACCU
    MOVLW	PWMperiod 
    MOVWF	NCO1INCL
    BSF		NCO1CON,N1EN ; NCO Enable
    
;INTC   
    BSF		IOCAN,ZC ; Int for ZC negativ front
    BSF		INTCON,IOCIE ; Enable Interrupt-on-Change
    BSF		INTCON,PEIE ; Peripheral Interrupt
    BSF		INTCON,GIE ; Global Interrupt Enable

    ; INIT VARS
    CLRF	FIRE
    CLRF	TMP
    MOVLW	FULLcount
    MOVWF	count
    

MAINLOOP
    BTFSS	    PIR1,NCO1IF     
    goto	    edge.rise
    BTFSS	    PORTA,PWMIN
    DECFSZ	    count
    goto	    clr.nco	
    BSF		    FIRE,FULL
    CLRF	    PR2_TMP
    MOVLW	    FULLcount
    MOVWF	    count    
clr.nco
    BCF		    PIR1,NCO1IF 
    CLRF	    NCO1ACCL
    CLRF	    NCO1ACCH
    CLRF	    NCO1ACCU    
    goto	    MAINLOOP
    
edge.rise
	movfw		PORTA				; load PORTA to Wreg            
	andlw           C.input_mask                    ; mask out I/O bits we're not interested in
        movwf           inputs.this_time                ; save result to variable
        xorwf           inputs.last_time,W              ; XOR last input value with current input value
        andwf           inputs.this_time,W              ; keep only bits that have changed from 0 to 1
        movwf           edgeR.detected                  ; save result to variable;

	movf		inputs.this_time,W              ; load result to variable
	xorwf           inputs.last_time,W              ; XOR last input value with current input value
        andwf           inputs.last_time,W              ; keep only bits that have changed from 0 to 1
        movwf           edgeF.detected

	movfw           inputs.this_time                ; copy input.this_time to 
        movwf           inputs.last_time

	BTFSC		edgeR.detected, PWMIN
	goto		tmr0.start
	BTFSC		edgeF.detected, PWMIN
	goto		tmr0.stop
	goto	    MAINLOOP 
	
tmr0.start
	CLRF	    NCO1ACCL
	CLRF	    NCO1ACCH
	CLRF	    NCO1ACCU	
	goto	    MAINLOOP
tmr0.stop
	BCF	    NCO1CON,N1EN ;NCO Disable
	MOVLW	    b'11110000'
	ANDWF	    NCO1ACCH,W
	ADDWF	    NCO1ACCU,W
	BTFSC	    FIRE,I
	goto	    tmr0.stop.1
	INCF	    PCLATH,F
	MOVWF	    TMP
	SWAPF	    TMP,W
	call	    Table
	MOVWF	    PR2_TMP
	DECF	    PCLATH,F	
	BCF	    FIRE,FULL
	
tmr0.stop.1
	BCF	    FIRE,I
	MOVLW	    FULLcount
	MOVWF	    count
	CLRF	    NCO1ACCL
	CLRF	    NCO1ACCH
	CLRF	    NCO1ACCU	
	BSF	    NCO1CON,N1EN ;NCO Enable	
	goto	    MAINLOOP
	
	ORG 0xFF
Table
	ADDWF       PCL,F
	RETLW	    0x00    ;0
	RETLW	    0x00    ;1
	RETLW	    0x00    ;2
	RETLW	    0x00    ;3
	RETLW	    0x00    ;4
	RETLW	    0x00    ;5
	RETLW	    0x00    ;6
	RETLW	    0x01    ;7
	RETLW	    0x02    ;8
	RETLW	    0x03    ;9
	RETLW	    0x04    ;A
	RETLW	    0x05    ;B
	RETLW	    0x06    ;C
	RETLW	    0x07    ;D
	RETLW	    0x08    ;E
	RETLW	    0x09    ;F
	; 1x
	RETLW	    0x0A    ;0
	RETLW	    0x0B    ;1
	RETLW	    0x0C    ;2
	RETLW	    0x0D    ;3
	RETLW	    0x0E    ;4
	RETLW	    0x0F    ;5
	RETLW	    0x10    ;6
	RETLW	    0x11    ;7
	RETLW	    0x12    ;8
	RETLW	    0x13    ;9
	RETLW	    0x14    ;A
	RETLW	    0x15    ;B
	RETLW	    0x16    ;C
	RETLW	    0x17    ;D
	RETLW	    0x18    ;E
	RETLW	    0x19    ;F
	;2
	RETLW	    0x1A    ;0
	RETLW	    0x1B    ;1
	RETLW	    0x1C    ;2
	RETLW	    0x1D    ;3
	RETLW	    0x1E    ;4
	RETLW	    0x1F    ;5
	RETLW	    0x20    ;6
	RETLW	    0x21    ;7
	RETLW	    0x22    ;8
	RETLW	    0x23    ;9
	RETLW	    0x24    ;A
	RETLW	    0x25    ;B
	RETLW	    0x26    ;C
	RETLW	    0x27    ;D
	RETLW	    0x28    ;E
	RETLW	    0x29    ;F
	;3
	RETLW	    0x2A    ;0
	RETLW	    0x2B    ;1
	RETLW	    0x2C    ;2
	RETLW	    0x2D    ;3
	RETLW	    0x2E    ;4
	RETLW	    0x2F    ;5
	RETLW	    0x30    ;6
	RETLW	    0x31    ;7
	RETLW	    0x32    ;8
	RETLW	    0x33    ;9
	RETLW	    0x34    ;A
	RETLW	    0x35    ;B
	RETLW	    0x36    ;C
	RETLW	    0x37    ;D
	RETLW	    0x38    ;E
	RETLW	    0x39    ;F
	;4
	RETLW	    0x3A    ;0
	RETLW	    0x3B    ;1
	RETLW	    0x3C    ;2
	RETLW	    0x3D    ;3
	RETLW	    0x3E    ;4
	RETLW	    0x3F    ;5
	RETLW	    0x40    ;6
	RETLW	    0x41    ;7
	RETLW	    0x42    ;8
	RETLW	    0x43    ;9
	RETLW	    0x44    ;A
	RETLW	    0x45    ;B
	RETLW	    0x46    ;C
	RETLW	    0x46    ;D
	RETLW	    0x47    ;E
	RETLW	    0x47    ;F
	;5
	RETLW	    0x48    ;0
	RETLW	    0x48    ;1
	RETLW	    0x49    ;2
	RETLW	    0x49    ;3
	RETLW	    0x4A    ;4
	RETLW	    0x4A    ;5
	RETLW	    0x4B    ;6
	RETLW	    0x4B    ;7
	RETLW	    0x4C    ;8
	RETLW	    0x4C    ;9
	RETLW	    0x4D    ;A
	RETLW	    0x4D    ;B
	RETLW	    0x4E    ;C
	RETLW	    0x4E    ;D
	RETLW	    0x4F    ;E
	RETLW	    0x4F    ;F
	;6
	RETLW	    0x50    ;0
	RETLW	    0x50    ;1
	RETLW	    0x51    ;2
	RETLW	    0x51    ;3
	RETLW	    0x52    ;4
	RETLW	    0x52    ;5
	RETLW	    0x53    ;6
	RETLW	    0x53    ;7
	RETLW	    0x54    ;8
	RETLW	    0x54    ;9
	RETLW	    0x55    ;A
	RETLW	    0x55    ;B
	RETLW	    0x56    ;C
	RETLW	    0x56    ;D
	RETLW	    0x57    ;E
	RETLW	    0x57    ;F
	;7
	RETLW	    0x58    ;0
	RETLW	    0x58    ;1
	RETLW	    0x59    ;2
	RETLW	    0x59    ;3
	RETLW	    0x5A    ;4
	RETLW	    0x5A    ;5
	RETLW	    0x5B    ;6
	RETLW	    0x5B    ;7
	RETLW	    0x5C    ;8
	RETLW	    0x5C    ;9
	RETLW	    0x5D    ;A
	RETLW	    0x5D    ;B
	RETLW	    0x5E    ;C
	RETLW	    0x5E    ;D
	RETLW	    0x5F    ;E
	RETLW	    0x5F    ;F
	;8
	RETLW	    0x60    ;0
	RETLW	    0x60    ;1
	RETLW	    0x61    ;2
	RETLW	    0x61    ;3
	RETLW	    0x62    ;4
	RETLW	    0x62    ;5
	RETLW	    0x63    ;6
	RETLW	    0x63    ;7
	RETLW	    0x64    ;8
	RETLW	    0x64    ;9
	RETLW	    0x65    ;A
	RETLW	    0x65    ;B
	RETLW	    0x66    ;C
	RETLW	    0x66    ;D
	RETLW	    0x67    ;E
	RETLW	    0x67    ;F
	;9
	RETLW	    0x68    ;0
	RETLW	    0x68    ;1
	RETLW	    0x69    ;2
	RETLW	    0x69    ;3
	RETLW	    0x6A    ;4
	RETLW	    0x6A    ;5
	RETLW	    0x6B    ;6
	RETLW	    0x6B    ;7
	RETLW	    0x6C    ;8
	RETLW	    0x6C    ;9
	RETLW	    0x6D    ;A
	RETLW	    0x6D    ;B
	RETLW	    0x6E    ;C
	RETLW	    0x6E    ;D
	RETLW	    0x6F    ;E
	RETLW	    0x6F    ;F
	;A
	RETLW	    0x70    ;0
	RETLW	    0x70    ;1
	RETLW	    0x71    ;2
	RETLW	    0x71    ;3
	RETLW	    0x72    ;4
	RETLW	    0x72    ;5
	RETLW	    0x73    ;6
	RETLW	    0x73    ;7
	RETLW	    0x74    ;8
	RETLW	    0x74    ;9
	RETLW	    0x75    ;A
	RETLW	    0x75    ;B
	RETLW	    0x76    ;C
	RETLW	    0x76    ;D
	RETLW	    0x77    ;E
	RETLW	    0x77    ;F
	;B
	RETLW	    0x78    ;0
	RETLW	    0x78    ;1
	RETLW	    0x79    ;2
	RETLW	    0x79    ;3
	RETLW	    0x7A    ;4
	RETLW	    0x7A    ;5
	RETLW	    0x7B    ;6
	RETLW	    0x7B    ;7
	RETLW	    0x7B    ;8
	RETLW	    0x7C    ;9
	RETLW	    0x7C    ;A
	RETLW	    0x7C    ;B
	RETLW	    0x7D    ;C
	RETLW	    0x7D    ;D
	RETLW	    0x7D    ;E
	RETLW	    0x7E    ;F
	;C
	RETLW	    0x7E    ;0
	RETLW	    0x7E    ;1
	RETLW	    0x7F    ;2
	RETLW	    0x7F    ;3
	RETLW	    0x7F    ;4
	RETLW	    0x80    ;5
	RETLW	    0x80    ;6
	RETLW	    0x80    ;7
	RETLW	    0x80    ;8
	RETLW	    0x80    ;9
	RETLW	    0x80    ;A
	RETLW	    0x80    ;B
	RETLW	    0x80    ;C
	RETLW	    0x80    ;D
	RETLW	    0x80    ;E
	RETLW	    0x80    ;F
	;D
	RETLW	    0x80    ;0
	RETLW	    0x80    ;1
	RETLW	    0x80    ;2
	RETLW	    0x80    ;3
	RETLW	    0x80    ;4
	RETLW	    0x80    ;5
	RETLW	    0x80    ;6
	RETLW	    0x80    ;7
	RETLW	    0x80    ;8
	RETLW	    0x80    ;9
	RETLW	    0x80    ;A
	RETLW	    0x80    ;B
	RETLW	    0x80    ;C
	RETLW	    0x80    ;D
	RETLW	    0x80    ;E
	RETLW	    0x80    ;F
	;E
	RETLW	    0x80    ;0
	RETLW	    0x80    ;1
	RETLW	    0x80    ;2
	RETLW	    0x80    ;3
	RETLW	    0x80    ;4
	RETLW	    0x80    ;5
	RETLW	    0x80    ;6
	RETLW	    0x80    ;7
	RETLW	    0x80    ;8
	RETLW	    0x80    ;9
	RETLW	    0x80    ;A
	RETLW	    0x80    ;B
	RETLW	    0x80    ;C
	RETLW	    0x80    ;D
	RETLW	    0x80    ;E
	RETLW	    0x80    ;F
	;F
	RETLW	    0x80    ;0
	RETLW	    0x80    ;1
	RETLW	    0x80    ;2
	RETLW	    0x80    ;3
	RETLW	    0x80    ;4
	RETLW	    0x80    ;5
	RETLW	    0x80    ;6
	RETLW	    0x80    ;7
	RETLW	    0x80    ;8
	RETLW	    0x80    ;9
	RETLW	    0x80    ;A
	RETLW	    0x80    ;B
	RETLW	    0x80    ;C
	RETLW	    0x80    ;D
	RETLW	    0x80    ;E
	RETLW	    0x80    ;F		
;====================================================================
      END

    
    
    
