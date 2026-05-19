proc showbmp
; enter - currentFile - name of the current file to display
; exit - display the current file
	mov [picHigh], 200
	mov [picWidth], 320
	mov [leftGap], 0
	mov [topGap], 0*320
	; Process BMP file
	call openFile
	call readHeader
	call readPalette
	call copyPal
	call copyBitmap
	call closeFile
ret
endp

proc finalScore
; enter - points - number of points acheived
; exit - display points in the right place on the ending screen.
	push ax bx cx dx
	; set cursor
	xor bx,bx	
	mov dh, 5  ; set line
	mov dl, 71   ; set column
	mov ah,2h
	int 10h

	mov al, [points]
	call printNumber  ; Display score
	pop dx cx bx ax
ret
endp finalScore
