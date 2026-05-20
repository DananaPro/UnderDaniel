; =========================================
; attacks.asm
; Handles bullet generation, movement, 
; and collision logic.
; =========================================

proc drawAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax
    mov [wid], 5
    mov [height], 5
    mov [color], 255    
    call drawRectangle
    ret
endp drawAttack

proc eraseAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax
    mov [wid], 5
    mov [height], 5
    mov [color], 0      
    call drawRectangle
    ret
endp eraseAttack

proc eraseAllBullets
    push cx si
    mov cx, MAX_BULLETS
    mov si, 0
eraseLoop:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax
    call eraseAttack
    add si, 2
    loop eraseLoop
    pop si cx
    ret
endp eraseAllBullets

proc checkCollision
    mov ax, [bulletX]
    add ax, 5
    cmp ax, [bowlX]
    jl safe
    mov ax, [bulletX]
    mov bx, [bowlX]
    add bx, 16
    cmp ax, bx
    jg safe
    mov ax, [bulletY]
    add ax, 5
    cmp ax, [bowlY]
    jl safe
    mov ax, [bulletY]
    mov bx, [bowlY]
    add bx, 16
    cmp ax, bx
    jg safe
    call takeDamage
    mov al, 1
    ret
safe:
    mov al, 0
    ret
endp checkCollision

proc takeDamage
    call eraseAttack    ; Erase the specific bullet that hit the player
    sub [hp], 4         ; Lose 4 HP per hit (Player has 5 lives total)
    cmp [hp], 0         ; Check if health reached 0 or less
    jle gameOverJump    ; If 0, trigger Game Over
    ret
gameOverJump:
    pop ax              ; Clean the stack (removes the return address from the proc)
    jmp gameOver        ; Jump to the Game Over routine
endp takeDamage

proc spawnBullet
    ; 1. Random X (Standard)
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxX]
    sub bx, [arenaMinX]
    sub bx, 5
    div bx
    add dx, [arenaMinX]
    mov [bulletX], dx

    ; 2. Start at the EXACT top level (arenaMinY)
    mov ax, [arenaMinY]
    mov [bulletY], ax

    ; 3. Generate a Short Random Delay (0 to 25 frames)
    call getRandom
    mov ax, [randNum]
    and ax, 25          ; Smaller number = More bullets falling!
    ; We return the delay value in AX to be saved into the array
    ret
endp spawnBullet

proc spawnAllBullets
    push cx si
    mov cx, MAX_BULLETS
    mov si, 0
spawnLoop:
    call spawnBullet      ; Sets X/Y and returns delay in AX
    mov [bulDelay + si], ax
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax
    
    add si, 2
    loop spawnLoop
    pop si cx
    ret
endp spawnAllBullets

proc handleAllBullets
    push cx si
    mov cx, MAX_BULLETS
    mov si, 0
bulletLoop:
    ; --- Check if bullet is still "waiting" to fall ---
    cmp [bulDelay + si], 0
    jbe startFalling      
    dec [bulDelay + si]   ; Count down the delay
    jmp nextBul           ; Skip this bullet until timer hits 0

startFalling:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax

    call eraseAttack

    ; Move down by a fixed speed of 2
    mov ax, [bulletSpeed] 
    add [bulY + si], ax
    mov ax, [bulY + si]
    mov [bulletY], ax

    call checkCollision
    cmp al, 1
    je resetOne

    mov ax, [bulY + si]
    cmp ax, [arenaMaxY]
    jge resetOne

    call drawAttack
    jmp nextBul

resetOne:
    call eraseAttack
    call spawnBullet      ; Returns new X and a new short Delay in AX
    mov [bulDelay + si], ax
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax

nextBul:
    add si, 2
    loop bulletLoop
    pop si cx
    ret
endp handleAllBullets