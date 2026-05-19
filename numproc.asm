proc printCharacter
; enter – character in al
; exit – printing the character
	push ax dx
	mov ah,2
	mov dl, al
	int 21h

	pop dx ax
ret
endp printCharacter



proc 	printNumber
; enter – number in al
; exit – printing the number digit by digit
    push 	ax bx cx dx
	call    compNumDigits
	mov 	bx,offset divisorTable
	xor     dx, dx
	mov     dl, 3
	sub     dl, [counter]
	add     bx, dx
nextDigit:
	xor 	ah,ah
	div 	[byte ptr bx]   	;al = quotient, ah = remainder
	add 	al,'0'
	call 	printCharacter  	;Draw the quotient
	mov 	al,ah          		;ah = remainder
	add 	bx,1            		;bx = address of next divisor
    cmp 	[byte ptr bx],0 	;Have all divisors been done?
    jne 	nextDigit
    pop 	dx cx bx ax
ret
endp 	printNumber


proc compNumDigits
; enter number in al, divisorTable - divisors for getting the digits
; exit - counter - number of digits in the number in al
	push ax
    push bx
	mov 	bx,offset divisorTable
	mov     [counter],0
nextDigit1:
	xor 	ah,ah 
	inc     [counter]
	div 	[byte ptr bx]   	;al = quotient, ah = remainder
	mov 	al,ch          		;ah = remainder
	add 	bx,1            		;bx = address of next divisor
    cmp 	[byte ptr bx],0 	;Have all divisors been done?
    jne 	nextDigit1
	pop bx
    pop ax
ret
endp

proc getRandom
; enter - ceed - counter for the location in cs
; exit - Return in randNum a number between 0 to 304 (256 + 32 + 16)
	push ax
    push bx
	in al, 40h		; read timer counter
	mov bx, [ceed]
	inc [ceed]
	mov ah, [byte cs:bx] 	; read one byte from memory
	xor al, ah 			; xor memory and counter
	and al, 11111111b 		; leave result between 0- to 255
	xor ah, ah
	mov [randNum], ax
	mov bx, [ceed]
	inc [ceed]
	mov ah, [byte cs:bx] 	; read one byte from memory
	xor al, ah 			; xor memory and counter
	and al, 00111111b 		; leave result between 0- to 63
	xor ah, ah
	add [randNum], ax
	mov bx, [ceed]
	inc [ceed]
	mov ah, [byte cs:bx] 	; read one byte from memory
	xor al, ah 			; xor memory and counter
	and al, 00001111b 		; leave result between 0- to 15
	xor ah, ah
	add [randNum], ax
	pop bx
    pop ax
ret
endp getRandom
