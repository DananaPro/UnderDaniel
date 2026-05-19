; ========================================================
; attacks.asm - Complete Physics & Collision Engine
; ========================================================

proc drawAttack
    mov ax, [bulletX]
    mov [x], ax
    mov ax, [bulletY]
    mov [y], ax
    mov [wid], 5
    mov [height], 5
    mov [color], 15     ; White bullets
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
    mov [color], 0      ; Black out
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
    sub [hp], 4
    cmp [hp], 0
    jle gameOverJump
    ret
gameOverJump:
    pop ax
    jmp gameOver
endp takeDamage

proc checkWalls
    mov ax, [bulletX]
    cmp ax, 12
    jle hitWall
    mov ax, [bulletX]
    cmp ax, 303
    jge hitWall
    mov ax, [bulletY]
    cmp ax, 12
    jle hitWall
    mov ax, [bulletY]
    cmp ax, 150
    jge hitWall
    mov al, 0
    ret
hitWall:
    mov al, 1
    ret
endp checkWalls

; --------------------------------------------------------
; DYNAMIC SPAWNING
; --------------------------------------------------------
proc spawnBullet
    mov ax, 0
    mov al, [currentWave]
    and ax, 3
    cmp ax, 0
    je spawnBouncing
    cmp ax, 1
    je spawnHoming
    cmp ax, 2
    je spawnSweeper
    cmp ax, 3
    je spawnRain

spawnBouncing:
    mov [bulletX], 160
    mov [bulletY], 80
    call getRandom
    mov ax, [randNum]
    and ax, 1
    cmp ax, 0
    je setDX_Neg
    mov ax, 3
    jmp set_DY_Bounce
setDX_Neg:
    mov ax, -3
set_DY_Bounce:
    mov [bulDX + si], ax

    call getRandom
    mov ax, [randNum]
    and ax, 1
    cmp ax, 0
    je setDY_Neg
    mov ax, 3
    jmp finalizeSpawn
setDY_Neg:
    mov ax, -3
    jmp finalizeSpawn

spawnHoming:
    call getRandom
    mov ax, [randNum]
    and ax, 1
    cmp ax, 0
    je homingLeft
    mov [bulletX], 300
    jmp homingY
homingLeft:
    mov [bulletX], 15
homingY:
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, 130
    div bx
    add dx, 15
    mov [bulletY], dx
    mov ax, 0
    mov [bulDX + si], ax
    mov [bulDY + si], ax
    jmp finalizeSpawn

spawnSweeper:
    mov [bulletX], 15
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, 130
    div bx
    add dx, 15
    mov [bulletY], dx
    mov ax, 5
    mov [bulDX + si], ax
    mov ax, 0
    mov [bulDY + si], ax
    jmp finalizeSpawn

spawnRain:
    call getRandom
    mov ax, [randNum]
    xor dx, dx
    mov bx, 280
    div bx
    add dx, 15
    mov [bulletX], dx
    mov [bulletY], 15
    mov ax, 0
    mov [bulDX + si], ax
    mov ax, 4
    mov [bulDY + si], ax
    
finalizeSpawn:
    call getRandom
    mov ax, [randNum]
    and ax, 31          
    ret
endp spawnBullet

proc spawnAllBullets
    push cx si
    mov cx, MAX_BULLETS
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
    pop si cx
    ret
endp spawnAllBullets

; --------------------------------------------------------
; PHYSICS ENGINE
; --------------------------------------------------------
proc handleAllBullets
    push cx si
    mov cx, MAX_BULLETS
    mov si, 0
bulletLoop:
    cmp [bulDelay + si], 0
    jbe startPhysics
    dec [bulDelay + si]
    jmp nextBul           

startPhysics:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax
    call eraseAttack      

    mov ax, 0
    mov al, [currentWave]
    and ax, 3
    cmp ax, 0
    je doBounce
    cmp ax, 1
    je doHome
    cmp ax, 2
    je doSweep
    cmp ax, 3
    je doRain

doBounce:
    mov ax, [bulX + si]
    add ax, [bulDX + si]
    mov [bulX + si], ax
    
    mov ax, [bulY + si]
    add ax, [bulDY + si]
    mov [bulY + si], ax
    
    mov ax, [bulX + si]
    cmp ax, 14
    jle revX
    cmp ax, 303
    jge revX
    jmp checkBY
revX:
    mov ax, [bulDX + si]
    neg ax
    mov [bulDX + si], ax
checkBY:
    mov ax, [bulY + si]
    cmp ax, 14
    jle revY
    cmp ax, 145
    jge revY
    jmp applyMove
revY:
    mov ax, [bulDY + si]
    neg ax
    mov [bulDY + si], ax
    jmp applyMove

doHome:
    mov ax, [bowlX]
    cmp ax, [bulX + si]
    jg homeIncX
    jl homeDecX
    jmp homeY
homeIncX:
    mov ax, [bulX + si]
    add ax, 1
    mov [bulX + si], ax
    jmp homeY
homeDecX:
    mov ax, [bulX + si]
    sub ax, 1
    mov [bulX + si], ax
homeY:
    mov ax, [bowlY]
    cmp ax, [bulY + si]
    jg homeIncY
    jl homeDecY
    jmp applyMove
homeIncY:
    mov ax, [bulY + si]
    add ax, 1
    mov [bulY + si], ax
    jmp applyMove
homeDecY:
    mov ax, [bulY + si]
    sub ax, 1
    mov [bulY + si], ax
    jmp applyMove

doSweep:
    mov ax, [bulX + si]
    add ax, [bulDX + si]
    mov [bulX + si], ax
    cmp ax, 303
    jge resetParticle
    jmp applyMove

doRain:
    mov ax, [bulY + si]
    add ax, [bulDY + si]
    mov [bulY + si], ax
    cmp ax, 145
    jge resetParticle
    jmp applyMove

resetParticle:
    call spawnBullet
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax
    jmp nextBul

applyMove:
    mov ax, [bulX + si]
    mov [bulletX], ax
    mov ax, [bulY + si]
    mov [bulletY], ax
    
    call checkCollision   
    cmp al, 1
    je forceReset
    
    call checkWalls
    cmp al, 1
    je forceReset
    jmp drawB

forceReset:
    call spawnBullet
    mov [bulDelay + si], ax
    mov ax, [bulletX]
    mov [bulX + si], ax
    mov ax, [bulletY]
    mov [bulY + si], ax

drawB:
    call drawAttack       

nextBul:
    add si, 2             
    loop bulletLoop       
    pop si cx
    ret
endp handleAllBullets

; --------------------------------------------------------
; ANTI-CRASH HOOKS (In case old wave timers call them)
; --------------------------------------------------------
proc execMoveRight
    ret
endp execMoveRight

proc execMoveLeft
    ret
endp execMoveLeft

proc execMoveUp
    ret
endp execMoveUp

proc execMoveDown
    ret
endp execMoveDown