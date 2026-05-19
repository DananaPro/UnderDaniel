; set address of data sement
setDS macro
    mov ax, @data
    mov ds, ax
endm

; set es to point to video memory
setES macro
	mov ax, 0A000h   ; make es point to video
	mov es, ax
endm

; get tav and print it
printTav macro tav
     mov dl , tav
     mov ah,2
     int 21h
endm

; go to start of new line 
newline macro
     mov dl,13
     mov ah,2
     int 21h
     mov dl,10
     mov ah,2
     int 21h
endm


; Set position for drawing a shape
setPos macro color, top, bottom
	mov bh,color; set color
	mov cx,top	; top coordinate
	mov dx,bottom	; bottom coordinate
endm

