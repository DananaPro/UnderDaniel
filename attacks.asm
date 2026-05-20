; --------------------------
; attacks.asm (inlined & corrected)
; - bullet size changed to 7x7 on boss waves
; - MAX_BULLETS usage matches DATASEG (12)
; - boss waves forced to 12 and 13
; - spawn/position math adjusted for 7px bullets
; --------------------------

; =========================================
; attacks.asm
; Handles bullet generation, movement, 
; collision logic, and wave patterns.
; =========================================

proc pickAttackPattern
    ; --- BOSS WAVE OVERRIDES ---
    cmp [WAVE_LEVEL], 12
    je forceBossWave1       ; Wave 12 = Falling Bullets
    cmp [WAVE_LEVEL], 13
    je forceBossWave2       ; Wave 13 = Chaos (pSix)
    ; --------------------------------

    call getRandom
    mov ax, [randNum]

    ; Break the RNG Sync Loop
    add ax, [bowlX]
    xor ah, ah
    add al, [WAVE_LEVEL]

    xor dx, dx
    mov bx, 7           ; Now dividing by 7 for 7 different wave types!
    div bx              ; The remainder (dx) will be 0 to 6

    ; Reset all counters to 0 first (Safest way to prevent leftovers)
    mov [activeDown], 0
    mov [activeUp], 0
    mov [activeLeft], 0
    mov [activeRight], 0

    cmp dl, 0
    je pZero
    cmp dl, 1
    je pOne
    cmp dl, 2
    je pTwo
    cmp dl, 3
    je pThree
    cmp dl, 4
    je pFour
    cmp dl, 5
    je pFive

pSix:                   ; BOSS PHASE 2: CHAOS (3 from all 4 sides = 12 total)
    mov [activeDown], 3
    mov [activeUp], 3
    mov [activeLeft], 3
    mov [activeRight], 3
    ret
pZero:                  ; BOSS PHASE 1: FALLING (12 total)
    mov [activeDown], 12
    mov [activeUp], 0
    mov [activeLeft], 0
    mov [activeRight], 0
    ret
pOne:                   ; PATTERN 1: ONLY RISING
    mov [activeUp], 10
    ret
pTwo:                   ; PATTERN 2: VERTICAL COMBO
    mov [activeDown], 5
    mov [activeUp], 5
    ret
pThree:                 ; PATTERN 3: ONLY LEFT-TO-RIGHT
    mov [activeLeft], 10
    ret
pFour:                  ; PATTERN 4: ONLY RIGHT-TO-LEFT
    mov [activeRight], 10
    ret
pFive:                  ; PATTERN 5: HORIZONTAL COMBO
    mov [activeLeft], 5
    mov [activeRight], 5
    ret

    ; --- Boss Jump Helpers ---
forceBossWave1:
    jmp pZero
forceBossWave2:
    jmp pSix
endp pickAttackPattern

; =========================================
; Drawing / Erasing Bullets
; =========================================

proc drawAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax

    ; If boss waves (12 or 13) use 7x7, else 5x5
    mov al, [WAVE_LEVEL]
    cmp al, 12
    jb normalSize
    cmp al, 13
    ja normalSize

    ; boss wave → 7x7
    mov ax, bulletWid
    mov [wid], ax
    mov [height], ax
    jmp doDraw

normalSize:
    mov ax, 5
    mov [wid], ax
    mov [height], ax

doDraw:
    mov [color], 255
    call drawRectangle
    ret
endp drawAttack

proc eraseAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax

    ; Match erase size to draw size
    mov al, [WAVE_LEVEL]
    cmp al, 12
    jb normalErase
    cmp al, 13
    ja normalErase

    mov ax, bulletWid
    mov [wid], ax
    mov [height], ax
    jmp doErase

normalErase:
    mov ax, 5
    mov [wid], ax
    mov [height], ax

doErase:
    mov [color], 0
    call drawRectangle
    ret
endp eraseAttack

; =========================================
; Collision
; =========================================

proc checkCollision
    ; -----------------------------
    ; X‑axis collision (5 or 7 px)
    ; -----------------------------
    mov ax, [bulletX]
    mov bl, [WAVE_LEVEL]
    cmp bl, 12
    jb x_use5
    cmp bl, 13
    ja x_use5
    add ax, 7           ; boss waves → 7
    jmp x_done
x_use5:
    add ax, 5           ; normal waves → 5
x_done:
    cmp ax, [bowlX]
    jl safe

    mov ax, [bulletX]
    mov bx, [bowlX]
    add bx, 16
    cmp ax, bx
    jg safe

    ; -----------------------------
    ; Y‑axis collision (5 or 7 px)
    ; -----------------------------
    mov ax, [bulletY]
    mov bl, [WAVE_LEVEL]
    cmp bl, 12
    jb y_use5
    cmp bl, 13
    ja y_use5
    add ax, 7           ; boss waves → 7
    jmp y_done
y_use5:
    add ax, 5           ; normal waves → 5
y_done:
    cmp ax, [bowlY]
    jl safe

    mov ax, [bulletY]
    mov bx, [bowlY]
    add bx, 16
    cmp ax, bx
    jg safe

    ; -----------------------------
    ; COLLISION OCCURRED
    ; -----------------------------
    call takeDamage
    mov al, 1
    ret

safe:
    mov al, 0
    ret
endp checkCollision

proc takeDamage
    call eraseAttack    ; Erases the bullet (but leaves a black square!)
    call drawBowl       ; Redraw the player immediately
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
    sub bx, 7            ; account for bullet width
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
    sub bx, 10
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

; =========================================
; Beep Sound (PC Speaker)
; =========================================

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

    ; 3. Hit-stop delay with SAFETY TIMEOUT
    mov ax, 40h
    mov es, ax
    mov bx, 6Ch
    mov eax, [es:bx]    ; Get current BIOS tick
    mov cx, 65000       ; <--- SAFETY COUNTER: Prevents infinite freeze!

wait_tick:
    call pollAudio      
    cmp eax, [es:bx]
    jne end_beep        ; If tick changed normally, jump to end!

    dec cx              ; Subtract 1 from safety counter
    jnz wait_tick       ; Keep waiting ONLY if cx is not 0

end_beep:
    ; 4. Turn OFF Speaker
    in al, 61h
    and al, 0FCh
    out 61h, al

    popa
    ret
endp beepSound

; =========================================
; LEFT-TO-RIGHT BULLETS
; =========================================

proc spawnLeftBullet
    ; 1. Start safely INSIDE the left wall
    mov ax, [arenaMinX]
    add ax, 10
    mov [bulletX], ax

    ; 2. Random Y between Top and Bottom
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxY]
    sub bx, [arenaMinY]
    sub bx, 7
    div bx
    add dx, [arenaMinY]
    mov [bulletY], dx

    ; 3. Random Delay
    call getRandom
    mov ax, [randNum]
    and ax, 25          
    ret
endp spawnLeftBullet

proc spawnAllLeftBullets
    push cx si
    mov cx, [activeLeft]
    cmp cx, 0
    je endSpawnLeft
    mov si, 0
spawnLeftLoop:
    call spawnLeftBullet    
    mov [leftBulDelay + si], ax
    mov ax, [bulletX]
    mov [leftBulX + si], ax
    mov ax, [bulletY]
    mov [leftBulY + si], ax
    add si, 2
    loop spawnLeftLoop
endSpawnLeft:
    pop si cx
    ret
endp spawnAllLeftBullets

proc handleAllLeftBullets
    push cx si
    mov cx, [activeLeft]
    cmp cx, 0
    je endHandleLeft
    mov si, 0
leftBulletLoop:
    cmp [leftBulDelay + si], 0
    jbe startMovingRight      
    dec [leftBulDelay + si]
    jmp nextLeftBul

startMovingRight:
    mov ax, [leftBulX + si]
    mov [bulletX], ax
    mov ax, [leftBulY + si]
    mov [bulletY], ax

    call eraseAttack

    ; Move RIGHT (Add speed to X)
    mov ax, [bulletSpeed] 
    add [leftBulX + si], ax
    mov ax, [leftBulX + si]
    mov [bulletX], ax

    call checkCollision
    cmp al, 1
    je resetLeftOne

    ; --- BOUNDARY CHECK ---
    mov ax, [leftBulX + si]
    mov bx, [arenaMaxX]
    sub bx, 10           ; Stop before touching the right wall
    cmp ax, bx
    jge resetLeftOne
    ; --------------------------

    mov ax, [leftBulX + si]
    cmp ax, [arenaMaxX]
    jge resetLeftOne

    call drawAttack
    jmp nextLeftBul

resetLeftOne:
    call eraseAttack
    call spawnLeftBullet    
    mov [leftBulDelay + si], ax
    mov ax, [bulletX]
    mov [leftBulX + si], ax
    mov ax, [bulletY]
    mov [leftBulY + si], ax

nextLeftBul:
    add si, 2
    loop leftBulletLoop
endHandleLeft:
    pop si cx
    ret
endp handleAllLeftBullets

proc eraseAllLeftBullets
    push cx si
    mov cx, [activeLeft]     
    cmp cx, 0
    je endEraseLeft
    mov si, 0
eraseLeftLoop:
    mov ax, [leftBulX + si]
    mov [bulletX], ax
    mov ax, [leftBulY + si]
    mov [bulletY], ax
    call eraseAttack
    add si, 2
    loop eraseLeftLoop
endEraseLeft:
    pop si cx
    ret
endp eraseAllLeftBullets

; =========================================
; RIGHT-TO-LEFT BULLETS
; =========================================

proc spawnRightBullet
    ; 1. Start safely INSIDE the right wall
    mov ax, [arenaMaxX]
    sub ax, 10
    mov [bulletX], ax

    ; 2. Random Y between Top and Bottom
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxY]
    sub bx, [arenaMinY]
    sub bx, 7
    div bx
    add dx, [arenaMinY]
    mov [bulletY], dx

    ; 3. Random Delay
    call getRandom
    mov ax, [randNum]
    and ax, 25          
    ret
endp spawnRightBullet

proc spawnAllRightBullets
    push cx si
    mov cx, [activeRight]
    cmp cx, 0
    je endSpawnRight
    mov si, 0
spawnRightLoop:
    call spawnRightBullet    
    mov [rightBulDelay + si], ax
    mov ax, [bulletX]
    mov [rightBulX + si], ax
    mov ax, [bulletY]
    mov [rightBulY + si], ax
    add si, 2
    loop spawnRightLoop
endSpawnRight:
    pop si cx
    ret
endp spawnAllRightBullets

proc handleAllRightBullets
    push cx si
    mov cx, [activeRight]
    cmp cx, 0
    je endHandleRight
    mov si, 0
rightBulletLoop:
    cmp [rightBulDelay + si], 0
    jbe startMovingLeft      
    dec [rightBulDelay + si]
    jmp nextRightBul

startMovingLeft:
    mov ax, [rightBulX + si]
    mov [bulletX], ax
    mov ax, [rightBulY + si]
    mov [bulletY], ax

    call eraseAttack

    ; Move LEFT (Subtract speed from X)
    mov ax, [bulletSpeed] 
    sub [rightBulX + si], ax
    mov ax, [rightBulX + si]
    mov [bulletX], ax

    call checkCollision
    cmp al, 1
    je resetRightOne

    ; --- BOUNDARY CHECK ---
    mov ax, [rightBulX + si]
    mov bx, [arenaMinX]
    add bx, 10           ; Stop before touching the left wall
    cmp ax, bx
    jle resetRightOne
    ; --------------------------

    mov ax, [rightBulX + si]
    cmp ax, [arenaMinX]
    jle resetRightOne

    call drawAttack
    jmp nextRightBul

resetRightOne:
    call eraseAttack
    call spawnRightBullet    
    mov [rightBulDelay + si], ax
    mov ax, [bulletX]
    mov [rightBulX + si], ax
    mov ax, [bulletY]
    mov [rightBulY + si], ax

nextRightBul:
    add si, 2
    loop rightBulletLoop
endHandleRight:
    pop si cx
    ret
endp handleAllRightBullets

proc eraseAllRightBullets
    push cx si
    mov cx, [activeRight]     
    cmp cx, 0
    je endEraseRight
    mov si, 0
eraseRightLoop:
    mov ax, [rightBulX + si]
    mov [bulletX], ax
    mov ax, [rightBulY + si]
    mov [bulletY], ax
    call eraseAttack
    add si, 2
    loop eraseRightLoop
endEraseRight:
    pop si cx
    ret
endp eraseAllRightBullets

; =========================================
; End of inlined attacks.asm
; =========================================
