proc movUp
    bowl2it
    call eraseItem
    sub [bowlY], 5
    ; Recalculate bowlPos from scratch: bowlPos = bowlY * 320 + bowlX
    mov ax, [bowlY]
    mov bx, 320
    mul bx              ; ax = bowlY * 320
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax   ; keep itemPos in sync too
    call drawBowl
    ret
endp movUp

proc movDown
    bowl2it
    call eraseItem
    add [bowlY], 5
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax
    call drawBowl
    ret
endp movDown

proc movLeft
    bowl2it
    call eraseItem
    sub [bowlX], 5
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax
    call drawBowl
    ret
endp movLeft

proc movRight
    bowl2it
    call eraseItem
    add [bowlX], 5
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax
    call drawBowl
    ret
endp movRight