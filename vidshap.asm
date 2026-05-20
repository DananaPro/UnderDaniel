; Print a pixel in location (x,y) with color 'color'
; parameters: x, y, color
proc drawPixel
	push ax bx cx dx
	mov cx,[x]
	mov dx,[y]
	xor bh,bh

	mov al,[byte ptr color]
	mov ah,0ch
	int 10h

	pop dx cx bx ax
ret
endp  drawPixel

; Print a horizontal line with width wid from location (x,y)
proc drawLine
	push cx [x]
	xor cx, cx
	mov cx, [wid]
lineloop:
	call drawPixel
	inc [x]
	loop lineloop
	pop [x] cx
ret
endp drawLine

proc drawRectangle
	push cx [y]
	xor cx, cx
	mov cx, [height]
hloop:
	call drawLine
	inc [y]
	loop hloop
	pop [y] cx
ret
endp drawRectangle
 
proc drawSquare
	push ax [height]
	mov ax, [wid]
	mov [height], ax
	call drawRectangle
	pop [height] ax
ret
endp drawSquare
 
proc eraseBowl
    push ax
    mov ax, [itemX]     ; Uses the previous position
    mov [x], ax
    mov ax, [itemY]     
    mov [y], ax
    mov [wid], 16       ; Matches your heart size
    mov [height], 16    
    mov [color], 0      ; Black color erases the heart
    call drawRectangle
    pop ax
    ret
endp eraseBowl