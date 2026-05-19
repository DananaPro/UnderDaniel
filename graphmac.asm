; set graph mod
graphMod macro
	mov ax, 13h
	int 10h
endm

;set text mode (2=black,3=colored)
textMod macro
mov ax,3
int 10h
endm

;wait for key pressed
wait4key macro
	mov ah,00h
	int 16h
endm

initMs macro
;initialize the mouse
	mov ax,0h
	int 33h
endm

showMs macro
	; show the mouse
	mov ax,1h
	int 33h
endm

;Activate speaker
actspkr macro
	in al, 61h
	or al, 00000011b
	out 61h, al
endm

; stop speaker
stopspkr macro
    ; close the speaker
	in al,61h
	and al,11111100b
	out 61h,al
endm

; set color and positions for shape drawing
setPos macro color, top, bottom
	mov bh,color; set color
	mov cx,top	; top coordinate
	mov dx,bottom	; bottom coordinate
endm

; anding and oring of an item drawing
drawItem macro
    call anding
	call oring
endm drawItem

; Sets the variables used in anding, oring for the bowl
; in: bowlX - x of current bowl position, bowlPos - current bowl position
; out: copy bowlX to itemX, copy bowlPos to itemPos.
bowl2it macro
    push ax
	mov ax, [bowlX]
	mov [itemX], ax
	mov ax, [bowlPos]
	mov [itemPos], ax
	pop ax
endm
