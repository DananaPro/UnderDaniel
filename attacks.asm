; ==============================================================================
; attacks.asm
; Handles bullet generation, movement, collision logic, and wave patterns.
; - Bullet size dynamically changes to 7x7 on boss waves (12 & 13)
; - MAX_BULLETS matches DATASEG (12 per side)
; - Spawn/position math adjusted to prevent bullets touching walls
; ==============================================================================

; ==============================================================================
; WAVE PATTERN GENERATOR
; Selects which sides shoot bullets this round
; ==============================================================================
proc pickAttackPattern
    ; --- BOSS WAVE OVERRIDES ---
    ; If we are on Wave 12 or 13, bypass the randomizer entirely
    cmp [WAVE_LEVEL], 12
    je forceBossWave1       ; Wave 12 = Falling Bullets (Boss Phase 1)
    cmp [WAVE_LEVEL], 13
    je forceBossWave2       ; Wave 13 = Chaos (Boss Phase 2)
    ; --------------------------------

    call getRandom
    mov ax, [randNum]

    ; --- BREAK THE RNG SYNC LOOP ---
    ; Simple RNGs can repeat patterns. By adding the player's current X position
    ; and the current Wave Level to the random number, it guarantees the sequence
    ; will feel completely unpredictable to the player.
    add ax, [bowlX]
    xor ah, ah
    add al, [WAVE_LEVEL]

    xor dx, dx
    mov bx, 7               ; Divide by 7 to get 7 different wave types
    div bx                  ; The remainder (stored in DX) will be 0 to 6

    ; Reset all bullet counters to 0 first (Safest way to prevent leftovers from last wave)
    mov [activeDown], 0
    mov [activeUp], 0
    mov [activeLeft], 0
    mov [activeRight], 0

    ; Jump to the selected pattern based on the remainder (dl)
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

    ; If dl is 6, it falls through to pSix (Normal Chaos)
    
pSix:                       ; PATTERN 6 / BOSS PHASE 2: CHAOS
    mov [activeDown], 3     ; 3 bullets from all 4 sides = 12 total
    mov [activeUp], 3
    mov [activeLeft], 3
    mov [activeRight], 3
    ret

pZero:                      ; PATTERN 0 / BOSS PHASE 1: FALLING
    mov [activeDown], 12    ; 12 bullets falling from the top
    mov [activeUp], 0
    mov [activeLeft], 0
    mov [activeRight], 0
    ret

pOne:                       ; PATTERN 1: ONLY RISING
    mov [activeUp], 10
    ret

pTwo:                       ; PATTERN 2: VERTICAL COMBO
    mov [activeDown], 5
    mov [activeUp], 5
    ret

pThree:                     ; PATTERN 3: ONLY LEFT-TO-RIGHT
    mov [activeLeft], 10
    ret

pFour:                      ; PATTERN 4: ONLY RIGHT-TO-LEFT
    mov [activeRight], 10
    ret

pFive:                      ; PATTERN 5: HORIZONTAL COMBO
    mov [activeLeft], 5
    mov [activeRight], 5
    ret

    ; --- Boss Jump Helpers ---
forceBossWave1:
    jmp pZero
forceBossWave2:
    jmp pSix
endp pickAttackPattern

; ==============================================================================
; DRAWING / ERASING BULLETS (Dynamic Sizing)
; ==============================================================================
proc drawAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax

    ; Check wave level to determine bullet size
    mov al, [WAVE_LEVEL]
    cmp al, 12
    jb normalSize           ; If Wave < 12, use normal 5x5
    cmp al, 13
    ja normalSize           ; If Wave > 13, use normal 5x5

    ; Boss wave (12 or 13) -> Set width/height to 7x7
    mov ax, bulletWid       ; defined as 7 in DATASEG
    mov [wid], ax
    mov [height], ax
    jmp doDraw

normalSize:                 ; Normal waves -> 5x5
    mov ax, 5
    mov [wid], ax
    mov [height], ax

doDraw:
    mov [color], 255        ; Color 255 (Usually White in 256-color palette)
    call drawRectangle
    ret
endp drawAttack

proc eraseAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax

    ; Match erase size to draw size so we don't leave trails
    mov al, [WAVE_LEVEL]
    cmp al, 12
    jb normalErase
    cmp al, 13
    ja normalErase

    mov ax, bulletWid       ; Erase 7x7
    mov [wid], ax
    mov [height], ax
    jmp doErase

normalErase:                ; Erase 5x5
    mov ax, 5
    mov [wid], ax
    mov [height], ax

doErase:
    mov [color], 0          ; Color 0 (Black) paints over the bullet to erase it
    call drawRectangle
    ret
endp eraseAttack

; ==============================================================================
; COLLISION DETECTION (Axis-Aligned Bounding Box - AABB)
; ==============================================================================
proc checkCollision
    ; -----------------------------
    ; X-axis collision check
    ; -----------------------------
    mov ax, [bulletX]
    mov bl, [WAVE_LEVEL]
    cmp bl, 12
    jb x_use5
    cmp bl, 13
    ja x_use5
    add ax, 7               ; Boss waves: Bullet Right Edge = X + 7
    jmp x_done
x_use5:
    add ax, 5               ; Normal waves: Bullet Right Edge = X + 5
x_done:
    ; If Bullet Right Edge < Player Left Edge, no collision
    cmp ax, [bowlX]
    jl safe

    ; If Bullet Left Edge > Player Right Edge (Player X + 16), no collision
    mov ax, [bulletX]
    mov bx, [bowlX]
    add bx, 16              
    cmp ax, bx
    jg safe

    ; -----------------------------
    ; Y-axis collision check
    ; -----------------------------
    mov ax, [bulletY]
    mov bl, [WAVE_LEVEL]
    cmp bl, 12
    jb y_use5
    cmp bl, 13
    ja y_use5
    add ax, 7               ; Boss waves: Bullet Bottom Edge = Y + 7
    jmp y_done
y_use5:
    add ax, 5               ; Normal waves: Bullet Bottom Edge = Y + 5
y_done:
    ; If Bullet Bottom Edge < Player Top Edge, no collision
    cmp ax, [bowlY]
    jl safe

    ; If Bullet Top Edge > Player Bottom Edge (Player Y + 16), no collision
    mov ax, [bulletY]
    mov bx, [bowlY]
    add bx, 16              
    cmp ax, bx
    jg safe

    ; -----------------------------
    ; COLLISION CONFIRMED
    ; -----------------------------
    call takeDamage
    mov al, 1               ; Return 1 (Collision True)
    ret

safe:
    mov al, 0               ; Return 0 (Safe)
    ret
endp checkCollision

proc takeDamage
    call eraseAttack        ; Erases the bullet so it doesn't hit twice
    call drawBowl           ; Redraw the player immediately over the black square
    call beepSound          ; Play the hit sound safely
    
    sub [hp], 4             ; Subtract 4 HP
    cmp [hp], 0             
    jle gameOverJump        ; If HP <= 0, trigger Game Over
    ret

gameOverJump:
    pop ax                  ; Clean up the stack before jumping out of the procedure
    jmp gameOver            ; Jump to the main game over loop
endp takeDamage

; ==============================================================================
; FALLING BULLETS (TOP TO BOTTOM)
; ==============================================================================
proc spawnBullet
    ; 1. Random X Position
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    
    ; Math: Calculate available width (MaxX - MinX - 7)
    mov bx, [arenaMaxX]
    sub bx, [arenaMinX]
    sub bx, 7               ; Account for max bullet width so it doesn't clip walls
    div bx
    add dx, [arenaMinX]     ; Add minimum X to the remainder
    mov [bulletX], dx

	; Start safely BELOW the top ceiling
    mov ax, [arenaMinY]
    add ax, 10
    mov [bulletY], ax

    ; 3. Random Delay (Staggers the bullets so they don't fall in a straight line)
    call getRandom
    mov ax, [randNum]
    and ax, 25              ; Bitwise AND 25 caps the delay at a small random number
    ret
endp spawnBullet

proc spawnAllBullets
    push cx si
    mov cx, [activeDown]
    cmp cx, 0
    je endSpawnDown         ; If no down bullets this wave, skip
    mov si, 0
spawnLoop:
    call spawnBullet      
    mov [bulDelay + si], ax ; Save random delay for this specific bullet
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax
    
    add si, 2               ; Words are 2 bytes, so increment array index by 2
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

    call eraseAttack        ; Erase old position

    ; Move DOWN
    mov ax, [bulletSpeed] 
    add [bulY + si], ax
    mov ax, [bulY + si]
    mov [bulletY], ax

    call checkCollision
    cmp al, 1
    je resetOne             

    ; --- NEW BOUNDARY CHECK (Saves the floor!) ---
    mov ax, [bulY + si]
    mov bx, [arenaMaxY]
    sub bx, 10              ; Stop 10 pixels before touching the floor
    cmp ax, bx
    jge resetOne            

    call drawAttack         
    jmp nextBul

resetOne:
    ; REMOVED 'call eraseAttack' here so it stops eating the background!
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
    call eraseAttack        ; Wipe the screen clean at the end of the wave
    add si, 2
    loop eraseLoop
endEraseDown:
    pop si cx
    ret
endp eraseAllBullets

; ==============================================================================
; RISING BULLETS (BOTTOM TO TOP)
; ==============================================================================
proc spawnUpBullet
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, [arenaMaxX]
    sub bx, [arenaMinX]
    sub bx, 10              ; Buffer to avoid right wall
    div bx
    add dx, [arenaMinX]
    mov [bulletX], dx

	; Start safely ABOVE the bottom floor
    mov ax, [arenaMaxY]     
    sub ax, 10
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

    ; Move UP (Subtract speed from Y)
    mov ax, [bulletSpeed] 
    sub [upBulY + si], ax
    mov ax, [upBulY + si]
    mov [bulletY], ax

    call checkCollision
    cmp al, 1
    je resetUpOne

    ; Boundary Check
    mov ax, [upBulY + si]
    cmp ax, [arenaMinY]
    jle resetUpOne          ; If it hit the ceiling, recycle

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

; ==============================================================================
; BEEP SOUND (Hardware PC Speaker)
; ==============================================================================
proc beepSound
    pusha
    
    ; 1. Configure PC Speaker
    mov al, 182             
    out 43h, al             
    
    mov ax, 2500            ; Deeper pitch for a better "crunch" sound
    out 42h, al             
    mov al, ah
    out 42h, al             

    ; 2. Turn ON Speaker
    in al, 61h              
    or al, 3                
    out 61h, al             

    ; 3. Wait for exactly 1 BIOS tick (~55ms delay)
    mov ax, 40h
    mov es, ax
    mov bx, 6Ch
    mov eax, [es:bx]        ; Read current hardware tick
wait_tick:
    call pollAudio          ; <--- CRITICAL: Keep feeding the audio buffer so it doesn't crash!
    cmp eax, [es:bx]        ; Has the tick changed?
    je wait_tick            ; If not, keep looping

    ; 4. Turn OFF Speaker
    in al, 61h
    and al, 0FCh            
    out 61h, al

    popa
    ret
endp beepSound

; ==============================================================================
; LEFT-TO-RIGHT BULLETS
; ==============================================================================
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
    sub bx, 7               ; Buffer to avoid bottom wall
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

    ; Move RIGHT
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
    sub bx, 10              ; Stop before touching the right wall
    cmp ax, bx
    jge resetLeftOne

    call drawAttack
    jmp nextLeftBul

resetLeftOne:
    ; REMOVED 'call eraseAttack'
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

; ==============================================================================
; RIGHT-TO-LEFT BULLETS
; ==============================================================================
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

    ; Move LEFT 
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
    add bx, 10              ; Stop before touching the left wall
    cmp ax, bx
    jle resetRightOne

    call drawAttack
    jmp nextRightBul

resetRightOne:
    ; REMOVED 'call eraseAttack'
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