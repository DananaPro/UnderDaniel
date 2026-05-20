; =========================================
; attacks.asm
; Handles bullet generation, movement, 
; collision logic, and wave patterns.
; =========================================

proc pickAttackPattern
    call getRandom
    mov ax, [randNum]
    
    ; --- THE FIX: Break the RNG Sync Loop! ---
    ; Add the player's unpredictable X position and the current wave level
    ; to scramble the math so the modulo doesn't get stuck in a loop.
    add ax, [bowlX]
    xor ah, ah
    add al, [WAVE_LEVEL]
    
    xor dx, dx
    mov bx, 3           ; Divide the scrambled number by 3
    div bx              ; The remainder (dx) will be 0, 1, or 2

    cmp dl, 0
    je patternZero
    cmp dl, 1
    je patternOne

patternTwo:             ; COMBO (5 Falling, 5 Rising)
    mov [activeDown], 5
    mov [activeUp], 5
    ret
patternZero:            ; ONLY FALLING (10 Falling, 0 Rising)
    mov [activeDown], 10
    mov [activeUp], 0
    ret
patternOne:             ; ONLY RISING (0 Falling, 10 Rising)
    mov [activeDown], 0
    mov [activeUp], 10
    ret
endp pickAttackPattern

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
    call eraseAttack    ; Erases the bullet (but leaves a black square!)
    call drawBowl       ; <--- THE FIX: Redraw the player immediately!
    call beepSound      ; Play the crunch sound safely
    sub [hp], 4         
    cmp [hp], 0         
    jle gameOverJump    
    ret
gameOverJump:
    pop ax              
    jmp gameOver        
endp takeDamage

; =========================================
; FALLING BULLETS (TOP TO BOTTOM)
; =========================================

proc spawnBullet
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxX]
    sub bx, [arenaMinX]
    sub bx, 5
    div bx
    add dx, [arenaMinX]
    mov [bulletX], dx

    mov ax, [arenaMinY]
    mov [bulletY], ax

    call getRandom
    mov ax, [randNum]
    and ax, 25          
    ret
endp spawnBullet

proc spawnAllBullets
    push cx si
    mov cx, [activeDown]
    cmp cx, 0
    je endSpawnDown
    mov si, 0
spawnLoop:
    call spawnBullet      
    mov [bulDelay + si], ax
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax
    
    add si, 2
    loop spawnLoop
endSpawnDown:
    pop si cx
    ret
endp spawnAllBullets

proc handleAllBullets
    push cx si
    mov cx, [activeDown]
    cmp cx, 0
    je endHandleDown
    mov si, 0
bulletLoop:
    cmp [bulDelay + si], 0
    jbe startFalling      
    dec [bulDelay + si]   
    jmp nextBul           

startFalling:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax

    call eraseAttack

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
    call spawnBullet      
    mov [bulDelay + si], ax
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax

nextBul:
    add si, 2
    loop bulletLoop
endHandleDown:
    pop si cx
    ret
endp handleAllBullets

proc eraseAllBullets
    push cx si
    mov cx, [activeDown]
    cmp cx, 0
    je endEraseDown
    mov si, 0
eraseLoop:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax
    call eraseAttack
    add si, 2
    loop eraseLoop
endEraseDown:
    pop si cx
    ret
endp eraseAllBullets


; =========================================
; RISING BULLETS (BOTTOM TO TOP)
; =========================================

proc spawnUpBullet
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxX]
    sub bx, [arenaMinX]
    sub bx, 5
    div bx
    add dx, [arenaMinX]
    mov [bulletX], dx

    mov ax, [arenaMaxY]
    mov [bulletY], ax

    call getRandom
    mov ax, [randNum]
    and ax, 25          
    ret
endp spawnUpBullet

proc spawnAllUpBullets
    push cx si
    mov cx, [activeUp]
    cmp cx, 0
    je endSpawnUp
    mov si, 0
spawnUpLoop:
    call spawnUpBullet    
    mov [upBulDelay + si], ax
    mov ax, [bulletX]
    mov [upBulX + si], ax
    mov ax, [bulletY]
    mov [upBulY + si], ax
    
    add si, 2
    loop spawnUpLoop
endSpawnUp:
    pop si cx
    ret
endp spawnAllUpBullets

proc handleAllUpBullets
    push cx si
    mov cx, [activeUp]
    cmp cx, 0
    je endHandleUp
    mov si, 0
upBulletLoop:
    cmp [upBulDelay + si], 0
    jbe startRising      
    dec [upBulDelay + si]
    jmp nextUpBul

startRising:
    mov ax, [upBulX + si]
    mov [bulletX], ax
    mov ax, [upBulY + si]
    mov [bulletY], ax

    call eraseAttack

    mov ax, [bulletSpeed] 
    sub [upBulY + si], ax
    mov ax, [upBulY + si]
    mov [bulletY], ax

    call checkCollision
    cmp al, 1
    je resetUpOne

    mov ax, [upBulY + si]
    cmp ax, [arenaMinY]
    jle resetUpOne

    call drawAttack
    jmp nextUpBul

resetUpOne:
    call eraseAttack
    call spawnUpBullet    
    mov [upBulDelay + si], ax
    mov ax, [bulletX]
    mov [upBulX + si], ax
    mov ax, [bulletY]
    mov [upBulY + si], ax

nextUpBul:
    add si, 2
    loop upBulletLoop
endHandleUp:
    pop si cx
    ret
endp handleAllUpBullets

proc eraseAllUpBullets
    push cx si
    mov cx, [activeUp]     
    cmp cx, 0
    je endEraseUp
    mov si, 0
eraseUpLoop:
    mov ax, [upBulX + si]
    mov [bulletX], ax
    mov ax, [upBulY + si]
    mov [bulletY], ax
    call eraseAttack
    add si, 2
    loop eraseUpLoop
endEraseUp:
    pop si cx
    ret
endp eraseAllUpBullets

proc beepSound
    pusha
    ; 1. Configure PC Speaker
    mov al, 182
    out 43h, al
    mov ax, 1500     
    out 42h, al
    mov al, ah
    out 42h, al
    
    ; 2. Turn ON Speaker
    in al, 61h
    or al, 3
    out 61h, al

    ; 3. Hit-stop delay that KEEPS AUDIO ALIVE
    mov ax, 40h
    mov es, ax
    mov bx, 6Ch
    mov eax, es:[bx]    ; Get current BIOS tick
wait_tick:
    call pollAudio      ; <--- THE FIX: Feed the audio buffer while frozen!
    cmp eax, es:[bx]
    je wait_tick        ; Loop until the hardware tick changes

    ; 4. Turn OFF Speaker
    in al, 61h
    and al, 0FCh
    out 61h, al
    
    popa
    ret
endp beepSound