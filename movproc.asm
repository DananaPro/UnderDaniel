proc drawBowl
; enter - bowlwid - width of the bowl, bowlClr - bowl color, bowl - shape array, bowlmask - mask 
; exit - draws the bowl
    push ax
	mov [itemwid], 16
	mov [itemh], 16
	mov al, [bowlclr]
	mov [color], al
	mov [itemOff], offset bowl
	mov [maskOff], offset bowlmask
    drawItem  
	pop ax
ret
endp drawBowl

proc eraseItem
    push ax [wid] [height] [x] [y]
    ; Use the player's ACTUAL Y and PREVIOUS X
    mov ax, [bowlY]
    mov [y], ax
    mov ax, [itemX]
    mov [x], ax
    ; Set the size to match your 16x16 heart
    mov [wid], 16
    mov [height], 16
    ; Use Color 0 (Black) to match your arena
    mov [color], 0  
    call drawRectangle
    pop [y] [x] [height] [wid] ax
ret
endp eraseItem


proc anding
; enter - itemPos = location, itemOff = offset of item to draw
; exit  - anding between character and screen

    push ax es di si cx

	mov ax, 0A000h    ; video
	mov es, ax
	mov di, [itemPos]
	mov si, [maskOff] ; offset bowlmask
	mov cx, [itemh]

andl:
    push cx
    mov cx, [itemwid]

xx:
    lodsb  ; load byte in ds:si into al
    and [es:di], al
    inc di
    loop xx

    add di, 320
    sub di, [itemwid]
	pop cx
    loop andl

    pop cx si di es ax
ret
endp anding

proc oring
; enter - itemPos = location, charOff = offset of character
; exit  - anding between character and screen

	; doPush ax, es, di, si, cx
	push ax es di si cx

	mov ax, 0A000h
	mov es, ax
	mov di, [itemPos]
	mov si, [itemOff] ; offset bowl
	mov cx, [itemh]

orl:
    push cx
    mov cx, [itemwid]

yy:
    lodsb
    or [es:di], al
    inc di
    loop yy

    add di, 320
    sub di, [itemwid]
    pop cx
    loop orl

    ; pop cx, si, di, es, ax
	pop cx si di es ax
ret
endp oring

