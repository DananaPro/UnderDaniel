jumps   ; allow unbounded jumps
include macros.asm
include graphmac.asm

IDEAL
P386          
MODEL small
STACK 1000h

DATASEG
; --------------------------
; Graphic Data Arrays
; --------------------------
include "bowl.asm"    ; character drawing (bowl/heart)
include "bowlM.asm"   ; character mask

; --------------------------
; Math & Random Number Variables
; --------------------------
divisorTable    db 100, 10, 1, 0
COUNTER         db 0
CEED            dw 0        ; Random seed value
RANDNUM         dw 0        ; Generated random number

; --------------------------
; Shape & Drawing Variables
; --------------------------
x           dw 0    
y           dw 0    
color       db 0    
wid         dw 0    
height      dw 0    

; --------------------------
; Player (Bowl/Heart) Variables
; --------------------------
bowlX       dw 140      
bowlY       dw 100      
bowlPos     dw 32140    
itemX       dw 140      ; Previous X for erasing
itemY       dw 100      ; Previous Y for erasing
itemPos     dw 32140    
bowlwid     equ 16      ; Heart is 16x16
itemwid     dw  16
itemh       dw  16      
bowlclr     db  40      
maskOff     dw  ?       
itemOff     dw  ?       

hp          db 20
points      db 0

; --------------------------
; Controls & Boundaries
; --------------------------
leftdwn     equ 4Bh 
rightdwn    equ 4Dh
updwn       equ 48h
downdwn     equ 50h
escKey      equ 01h
enterKey    equ 0Dh     

arenaMinX   dw 14      
arenaMaxX   dw 310      
arenaMinY   dw 14       
arenaMaxY   dw 150      

; --------------------------
; Attack & Wave Variables
; --------------------------
waveTimer   dw 0        
isBreak     db 0        ; 0 = Attacking, 1 = Break Time
WAVE_LEVEL  db 1        

MAX_BULLETS    equ 10
bulX           dw MAX_BULLETS dup (0)
bulY           dw MAX_BULLETS dup (0)
bulDelay       dw MAX_BULLETS dup (0)
bulletX        dw 0        ; Temp variable for drawing logic
bulletY        dw 0        ; Temp variable for drawing logic
bulletSpeed    dw 2

hpMsg          db 'HP: $'

; --------------------------
; File Variables
; --------------------------
startfile       db 'intro.bmp',0 
endfile         db 'gameover.bmp',0 
gamebg          db 'danbg.bmp',0
instfile        db 'lore.bmp',0     

; --- Audio Variables ---
menuSnd         db 'menu.raw',0
batlSnd         db 'batl.raw',0   
deadSnd         db 'dead.raw',0    ; <--- ADD THIS LINE!

baseSP      	dw 0        ; Saves a clean state of our memory stack
filehandle      dw ? 
currentFile     dw ? 
Header          db 54 dup (0)
Palette         db 256*4 dup (0)
ScrLine         db 320 dup (0)
ErrorMsg        db 'Error in open file$'
picHigh         dw ? 
picWidth        dw ? 
leftGap         dw ?  
topGap          dw ?  
place           dw ? 

CODESEG

start:
    mov ah, 4Ah
    mov bx, 8192      
    int 21h

    setDS           
    setES           

    ; Initialize the DMA memory buffer ONCE
    call initAudioSystem

    graphMod        

    ; Start Menu Music Streaming
    mov dx, offset menuSnd
    call playStreamingAudio

    mov [currentFile], offset startfile
    call showbmp

    ; --- 2. MENU SELECTION ---
waitForStartKey:
    call pollAudio

    mov ah, 01h         ; Check if key is PRESSED (Non-blocking)
    int 16h
    jz waitForStartKey  ; If no key, loop back and play music
    
    ; Key was pressed! Consume it from the buffer
    mov ah, 00h
    int 16h
    
    ; Exit if ESC is pressed at the start menu
    cmp ah, escKey  
    je exitJ        

    ; Start if Enter is pressed
    cmp al, enterKey 
    je startGameImmediately

    ; Lore if 'C' is pressed
    or al, 20h      
    cmp al, 'c'
    je displayLore

    jmp waitForStartKey

displayLore:
    mov [currentFile], offset instfile
    call showbmp    
    
waitForEnterFromLore:
    call pollAudio      ; Keep music streaming while reading lore!

    ; Check if key is PRESSED (Non-blocking)
    mov ah, 01h
    int 16h
    jz waitForEnterFromLore

    ; Consume the key
    mov ah, 00h
    int 16h

    cmp ah, escKey   ; Allow exiting from the lore screen too
    je exitJ
    cmp al, enterKey 
    jne waitForEnterFromLore

startGameImmediately:
    mov [currentFile], offset gamebg
    call showbmp    

    ; --- Switch to Battle Music ---
    mov dx, offset batlSnd
    call playStreamingAudio

gamestart:           
    mov [baseSP], sp
    call initGame
    call spawnAllBullets

mainLoop:   
    call pollAudio
    call delay
    inc [waveTimer]

    ; Check for Break state
    cmp [isBreak], 1
    je handleBreak

    ; --- ATTACK WAVE ---
    call handleAllBullets  
    call drawHealthBar
    
    cmp [waveTimer], 420 ; 7 Seconds
    jl checkInput       
    
    mov [isBreak], 1
    mov [waveTimer], 0  
    call eraseAllBullets    
	inc [WAVE_LEVEL]
    jmp checkInput

handleBreak:
    ; --- BREAK TIME ---
    call drawHealthBar
    cmp [waveTimer], 120 ; 2 Seconds
    jl checkInput       

    mov [isBreak], 0
    mov [waveTimer], 0  
    call spawnAllBullets
     
checkInput:
    mov ah, 01h
    int 16h
    jz mainLoop

    mov ah, 00h
    int 16h
    or al, 20h ; Normalize to lowercase

    cmp ah, updwn
    je moveUpJ
    cmp al, 'w'
    je moveUpJ
    cmp ah, downdwn
    je moveDownJ
    cmp al, 's'
    je moveDownJ
    cmp ah, leftdwn
    je moveLeftJ
    cmp al, 'a'
    je moveLeftJ
    cmp ah, rightdwn
    je moveRightJ
    cmp al, 'd'
    je moveRightJ
    cmp ah, escKey
    je exitJ
    jmp mainLoop

; Jump helpers for range
moveUpJ:    jmp doMoveUp
moveDownJ:  jmp doMoveDown
moveLeftJ:  jmp doMoveLeft
moveRightJ: jmp doMoveRight
exitJ:      jmp exit

; --- Movement Handlers ---
doMoveLeft:
    mov ax, [bowlX]
    sub ax, 5
    cmp ax, [arenaMinX]
    jl mainLoop
    mov [itemX], ax
    call movLeft
    jmp mainLoop

doMoveRight:
    mov ax, [bowlX]
    add ax, 5
    add ax, 16
    cmp ax, [arenaMaxX]
    jg mainLoop
    mov [itemX], ax
    call movRight
    jmp mainLoop

doMoveUp:
    mov ax, [bowlY]
    sub ax, 5
    cmp ax, [arenaMinY]
    jl mainLoop
    mov ax, [bowlX]
    mov [itemX], ax
    call movUp
    jmp mainLoop

doMoveDown:
    mov ax, [bowlY]
    add ax, 5
    add ax, 16
    cmp ax, [arenaMaxY]
    jg mainLoop
    mov ax, [bowlX]
    mov [itemX], ax
    call movDown
    jmp mainLoop

gameOver:
    mov sp, [baseSP]

    ; --- Switch to Game Over music! ---
    mov dx, offset deadSnd
    call playStreamingAudio

    ; Draw the ending screen
    mov [currentFile], offset endfile
    call showbmp 

waitForGameOverKey:
    call pollAudio      ; Keep streaming music while waiting!

    ; Check if key is PRESSED (Non-blocking)
    mov ah, 01h
    int 16h
    jz waitForGameOverKey ; If no key, loop and keep playing music

    ; Key was pressed! Consume it from the buffer
    mov ah, 00h
    int 16h

    cmp ah, escKey
    je exit

    cmp al, enterKey
    jne waitForGameOverKey
    
    ; --- RESTART LOGIC ---
    mov [hp], 20       ; Reset health
	mov [WAVE_LEVEL], 1; Reset Wave
    mov [waveTimer], 0 ; Reset timer
    mov [isBreak], 0   ; Ensure we aren't in break mode
    
    ; Jump back up to the routine that handles the background AND the battle music!
    jmp startGameImmediately
    
    ; Redraw the background and jump back to the start
    mov [currentFile], offset gamebg
    call showbmp
    jmp gamestart

exit:
	call stopStreamingAudio
    textmod               
    mov ax, 4c00h         
    int 21h

; =========================================
; Game Procedures 
; =========================================
proc initGame
    call drawBowl
    ret
endp initGame

proc delay
    mov ah, 86h
    mov cx, 0
    mov dx, 33333     
    int 15h
    ret
endp delay

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
    mov ax, [bulletSpeed] ; Ensure this is set to 2 in DATASEG
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

proc drawHealthBar
    push ax bx dx

    ; -----------------------------------------
    ; 1. Print the Wave Counter
    ; -----------------------------------------
    ; Set Cursor Position
    mov ah, 2
    mov bh, 0
    mov dh, 21          ; Row 21 (Aligned with HP text)
    mov dl, 27          ; Column 27 (To the right side)
    int 10h

    ; Set text color to Light Green (10) for VGA mode text
    mov bl, 10

    ; Print "Wave: " manually to bypass DOS string bugs
    mov ah, 2
    mov dl, 'W'
    int 21h
    mov dl, 'a'
    int 21h
    mov dl, 'v'
    int 21h
    mov dl, 'e'
    int 21h
    mov dl, ':'
    int 21h
    mov dl, ' '
    int 21h

    ; Print Current Wave Number (Manually divided, just like HP)
    xor ax, ax
    mov al, [WAVE_LEVEL]
    mov bl, 10          ; Divide by 10 (and keeps text color Light Green!)
    div bl              
    
    push ax             
    
    add al, '0'         ; Tens Digit
    mov dl, al
    mov ah, 2
    int 21h
    
    pop ax              
    mov al, ah          
    add al, '0'         ; Ones Digit
    mov dl, al
    mov ah, 2
    int 21h

    ; -----------------------------------------
    ; 2. Print Current HP Text
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 21          
    mov dl, 12          
    int 10h

    ; Extract and Print Current HP 
    xor ax, ax
    mov al, [hp]        
    mov bl, 10
    div bl              
    
    push ax             
    
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h
    
    pop ax              
    mov al, ah          
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h

    ; Print the static "/20 HP" string
    mov ah, 2
    mov dl, '/'
    int 21h
    mov dl, '2'
    int 21h
    mov dl, '0'
    int 21h
    mov dl, ' '
    int 21h
    mov dl, 'H'
    int 21h
    mov dl, 'P'
    int 21h

    ; -----------------------------------------
    ; 3. Draw the Visual Bar Background (Gray)
    ; -----------------------------------------
    mov [x], 120
    mov [y], 180
    mov [wid], 80
    mov [height], 5
    mov [color], 8      
    call drawRectangle

    ; -----------------------------------------
    ; 4. Draw the Red Health Fill
    ; -----------------------------------------
    xor ax, ax
    mov al, [hp]
    cmp al, 0
    jle skipFill        
    
    mov bx, 4           
    mul bx              
    mov [wid], ax
    mov [color], 63     ; Bright Red
    call drawRectangle

skipFill:
    pop dx bx ax
    ret
endp drawHealthBar

; --------------------------
; Include Procedures
; --------------------------
; Includes must stay at the bottom to avoid "Undefined symbol" errors
include "movproc.asm" 
include "vidshap.asm" 
include "bmpproc.asm" 
include "fileproc.asm"  
include "numproc.asm"   
include "movarrow.asm"  
include "dmaaudio.asm"

END start