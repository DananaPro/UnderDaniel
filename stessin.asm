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
isFreezing      db 0    ; 0 = Normal, 1 = Stop all drawing immediately

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
WAVE_LEVEL  db 10        ; Start at wave 1
BEST_WAVE   db 1
CHECKPOINT      db 1        ; Saves your progress!
STORY_STATE     db 0        ; Tracks which spooky room you are in (1 = Pre-Boss, 2 = Post-Boss)    

MAX_BULLETS    equ 12     ; Increased to 12 for boss waves
bulletWid      equ 7

bulX           dw MAX_BULLETS dup (0)
bulY           dw MAX_BULLETS dup (0)
bulDelay       dw MAX_BULLETS dup (0)

upBulX         dw MAX_BULLETS dup (0)
upBulY         dw MAX_BULLETS dup (0)
upBulDelay     dw MAX_BULLETS dup (0)

leftBulX       dw MAX_BULLETS dup (0)
leftBulY       dw MAX_BULLETS dup (0)
leftBulDelay   dw MAX_BULLETS dup (0)

rightBulX      dw MAX_BULLETS dup (0)
rightBulY      dw MAX_BULLETS dup (0)
rightBulDelay  dw MAX_BULLETS dup (0)

activeDown     dw 0   
activeUp       dw 0    
activeLeft     dw 0
activeRight    dw 0

bulletX        dw 0        ; Temp variable for drawing logic
bulletY        dw 0        ; Temp variable for drawing logic
bulletSpeed    dw 2
oldHp          db 255      ; Tracks when HP changes
oldWave        db 255      ; Tracks when Wave changes

hpMsg          db 'HP: $'

; --- File Variables ---
startfile       db 'intro.bmp',0 
endfile         db 'gover2.bmp',0 
gamebg          db 'danbg.bmp',0
instfile        db 'lore.bmp',0
spookyFile      db 'spookyrm.bmp',0
spookyFile2     db 'spooky2.bmp',0
bossRmFile      db 'bossrm.bmp',0
bossBgFile      db 'bossbg.bmp',0
winFile         db 'win.bmp',0

; --- Audio Variables ---
menuSnd         db 'menu.raw',0
batlSnd         db 'batl.raw',0   
deadSnd         db 'dead.raw',0
bossSnd         db 'boss.raw',0  
winSnd          db 'win.raw',0

baseSP          dw 0        ; Saves a clean state of our memory stack
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
    mov [isFreezing], 0
    mov [baseSP], sp
    call initGame
    call pickAttackPattern
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets

mainLoop:   
    call pollAudio
    
    ; --- IF FREEZING, SKIP ALL LOGIC ---
    cmp [isFreezing], 1
    je checkInput
    ; ---------------------------------------
    
    call delay
    inc [waveTimer]

    ; Check for Break state
    cmp [isBreak], 1
    je handleBreak

    ; --- ATTACK WAVE ---
    call handleAllBullets  
    call handleAllUpBullets
    call handleAllLeftBullets
    call handleAllRightBullets
    call drawHealthBar
    
    cmp [waveTimer], 420 ; 7 Seconds
    jl checkInput       
    
    mov [isBreak], 1
    mov [waveTimer], 0
    call eraseAllBullets
    call eraseAllUpBullets
    call eraseAllLeftBullets
    call eraseAllRightBullets
    inc [WAVE_LEVEL]

    cmp [WAVE_LEVEL], 11     ; Did we just beat Wave 10?
    je triggerSpooky1

    cmp [WAVE_LEVEL], 14     ; Did we just beat Wave 13 (Boss Part 2)?
    je triggerSpooky2
    
    ; If it's a normal wave (like transitioning from Boss 1 to Boss 2), keep playing!
    mov [isFreezing], 0
    jmp checkInput
    
triggerSpooky1:
    mov [isFreezing], 1
    jmp goSpooky1

triggerSpooky2:
    mov [isFreezing], 1
    jmp goSpooky2
    ; ---------------------------------

handleBreak:
    call drawHealthBar
    cmp [waveTimer], 120
    jl checkInput        

    mov [isBreak], 0
    mov [waveTimer], 0
    call pickAttackPattern
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets
     
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

; =========================================
; STORY TRANSITIONS & MINI-GAME
; =========================================
goSpooky1:
    mov [STORY_STATE], 1
    mov [currentFile], offset spookyFile
    jmp setupSpookyRoom

goSpooky2:
    mov [STORY_STATE], 2
    mov [currentFile], offset spookyFile2
    jmp setupSpookyRoom

setupSpookyRoom:
    ; 1. Clear the old heart from the battle screen FIRST
    call eraseBowl      

    ; 2. Now load the room
    call showbmp        

    ; 3. Teleport and draw at lower middle so player has space to walk up
    mov ax, 140
    mov [bowlX], ax
    mov [itemX], ax
    mov ax, 130
    mov [bowlY], ax
    mov [itemY], ax

    ; Recalculate bowlPos/itemPos
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax

    call drawBowl           ; 3. Draw Heart
    jmp spookyLoop          ; 4. Enter movement loop

spookyLoop:
    call pollAudio
    mov ah, 01h
    int 16h
    jz spookyLoop

    mov ah, 00h
    int 16h
    or al, 20h

    cmp ah, updwn
    je spookyMoveUp
    cmp al, 'w'
    je spookyMoveUp
    cmp ah, escKey
    je exitJ
    jmp spookyLoop

spookyMoveUp:
    ; 1. Erase the old heart first by replacing the image over it
	call showbmp
	
    ; 2. Save previous position into itemX/itemY for next erase
    mov ax, [bowlX]
    mov [itemX], ax
    mov ax, [bowlY]
    mov [itemY], ax

    ; 3. Move up
    sub ax, 5
    mov [bowlY], ax

    ; 4. Recalculate bowlPos/itemPos
    mov bx, 320
    mov dx, ax
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax

    ; 5. Draw new bowl
    call drawBowl

    ; 6. CHECK IF AT DOOR (Y=70)
    cmp [bowlY], 70              
    jle spookyDoorReached
    jmp spookyLoop

spookyDoorReached:
    cmp [STORY_STATE], 1
    je goBossDialogue
    cmp [STORY_STATE], 2
    je goWinScreen

goBossDialogue:
    mov [WAVE_LEVEL], 12    ; Force the wave to 12
    mov [isFreezing], 1     ; Stop mainLoop logic during dialogue
    mov [currentFile], offset bossRmFile
    call showbmp
    mov [CHECKPOINT], 12

waitBossKey:
    call pollAudio
    mov ah, 01h
    int 16h
    jz waitBossKey
    mov ah, 00h
    int 16h
    cmp al, enterKey
    jne waitBossKey

    ; --- ENTER WAVE 12 (BOSS FIGHT) ---
    mov [currentFile], offset bossBgFile
    call showbmp            
    mov dx, offset bossSnd
    call playStreamingAudio 

    ; Reset game state for Boss
    mov [isFreezing], 0     ; UNFREEZE HERE!
    mov [isBreak], 0
    mov [waveTimer], 0

    ; Setup player for Boss (centered)
    mov ax, 140
    mov [bowlX], ax
    mov ax, 100
    mov [bowlY], ax

    ; Recalculate bowlPos/itemPos
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax
	mov ax, [bowlX]
	mov [itemX], ax

	mov ax, [bowlY]
	mov [itemY], ax

    call drawBowl

    ; Prepare boss waves: pickAttackPattern will force wave 12 & 13
    call pickAttackPattern
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets

    jmp mainLoop           ; Jump back to main attack loop

goWinScreen:
    mov dx, offset winSnd
    call playStreamingAudio
    mov [currentFile], offset winFile
    call showbmp

waitWinKey:
    call pollAudio
    mov ah, 01h
    int 16h
    jz waitWinKey
    mov ah, 00h
    int 16h
    cmp ah, escKey
    je exitJ
    cmp al, enterKey
    jne waitWinKey

    call stopStreamingAudio

    ; Hard Reset for a completely new game
    mov [CHECKPOINT], 1     
    mov [WAVE_LEVEL], 1
    mov [hp], 20       
    jmp startGameImmediately

gameOver:
    mov sp, [baseSP]

    ; --- CHECK FOR NEW HIGH SCORE ---
    mov al, [WAVE_LEVEL]
    cmp al, [BEST_WAVE]
    jle skipHighScore       ; If current wave is LESS or EQUAL to best, skip updating
    mov [BEST_WAVE], al     ; NEW HIGH SCORE! Save it to BEST_WAVE
skipHighScore:

    ; --- Switch to Game Over music! ---
    mov dx, offset deadSnd
    call playStreamingAudio

    ; Draw the ending screen
    mov [currentFile], offset endfile
    call showbmp 

    ; -----------------------------------------
    ; Print Final Wave Score on Game Over Screen
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 12          ; Row 12
    mov dl, 4           ; Column 4
    int 10h

    mov bl, 14          ; Yellow text
    mov ah, 2
    mov dl, 'W'
    int 21h
    mov dl, 'A'
    int 21h
    mov dl, 'V'
    int 21h
    mov dl, 'E'
    int 21h
    mov dl, 'S'
    int 21h
    mov dl, ':'
    int 21h
    mov dl, ' '
    int 21h

    xor ax, ax
    mov al, [WAVE_LEVEL]
    mov cl, 10          
    div cl              
    
    push ax             
    add al, '0'         
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h
    
    pop ax              
    mov al, ah          
    add al, '0'         
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h

    ; -----------------------------------------
    ; Print BEST Wave Score 
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 14          ; Row 14 (Two lines exactly under the current score)
    mov dl, 4           ; Column 4
    int 10h

    mov bl, 14          ; Yellow text
    mov ah, 2
    mov dl, 'B'
    int 21h
    mov dl, 'E'
    int 21h
    mov dl, 'S'
    int 21h
    mov dl, 'T'
    int 21h
    mov dl, ':'
    int 21h
    mov dl, ' '
    int 21h

    xor ax, ax
    mov al, [BEST_WAVE] ; <--- Use the BEST_WAVE variable this time!
    mov cl, 10          
    div cl              
    
    push ax             
    add al, '0'         
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h
    
    pop ax              
    mov al, ah          
    add al, '0'         
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h
    ; -----------------------------------------

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
    mov [hp], 20       
    
    ; Load the Checkpoint instead of forcing Wave 1!
    mov al, [CHECKPOINT]
    mov [WAVE_LEVEL], al
    
    mov [waveTimer], 0 
    mov [isBreak], 0   
    mov [oldHp], 255   
    mov [oldWave], 255 
    
    ; --- NEW: Did they die on the boss? ---
    cmp [CHECKPOINT], 12
    je goBossDialogue       ; Skip the game loop and teleport back to the dialogue room!
    ; --------------------------------------

    ; Otherwise, normal restart
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

proc drawHealthBar
    push ax bx dx

    ; -----------------------------------------
    ; 1. Print the Wave Counter
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 22          ; Row 22 (Perfectly aligned with HP text)
    mov dl, 27          
    int 10h

    mov bl, 10          ; Light Green
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

    xor ax, ax
    mov al, [WAVE_LEVEL]
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

    ; -----------------------------------------
    ; 2. Print Current HP Text
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 22          ; Row 22
    mov dl, 2           ; Shifted far left so it doesn't hit the graphics bar
    int 10h

    xor ax, ax
    mov al, [hp]        
    mov bl, 10          ; Light Green Text
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
    ; 3. Draw the Visual Health Background
    ; -----------------------------------------
    mov [x], 100        ; Moved to X=100 so it sits nicely next to the text
    mov [y], 178        ; Y=178 centers the rectangle perfectly on Row 22 text
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
    jle drawTimerSection        
    
    mov bx, 4           
    mul bx              
    mov [wid], ax
    mov [color], 63     ; Bright Red Health
    call drawRectangle

drawTimerSection:
    ; -----------------------------------------
    ; 5. Print "TIME" Text
    ; -----------------------------------------
    mov ah, 2
    mov bh, 0
    mov dh, 24          ; Row 24 (Sits exactly under HP text)
    mov dl, 2           ; Shifted far left
    int 10h

    mov bl, 10          ; Light Green to match HP text

    mov ah, 2
    mov dl, 'T'
    int 21h
    mov dl, 'I'
    int 21h
    mov dl, 'M'
    int 21h
    mov dl, 'E'
    int 21h

    ; -----------------------------------------
    ; 6. Draw Timer Bar Background
    ; -----------------------------------------
    mov [x], 100
    mov [y], 194        ; Y=194 centers it perfectly on Row 24 text
    mov [wid], 84       
    mov [height], 5
    mov [color], 8      ; Gray background
    call drawRectangle

    ; -----------------------------------------
    ; 7. Calculate & Draw Shrinking Timer Fill
    ; -----------------------------------------
    cmp [isBreak], 1
    je calcBreakTimer

    ; -- Attack Phase -- 
    mov ax, [waveTimer] 
    mov bl, 5           
    div bl              
    
    mov dl, 84
    sub dl, al          
    xor dh, dh
    mov [wid], dx
    mov [color], 63     ; CHANGED TO 63: Bright Red to perfectly match Health!
    jmp doTimerFill

calcBreakTimer:
    ; -- Break Phase -- 
    mov ax, [waveTimer] 
    mov bx, 7
    mul bx              
    mov bx, 10
    div bx              
    
    mov dx, 84
    sub dx, ax          
    mov [wid], dx
    mov [color], 63

doTimerFill:
    cmp [wid], 0
    jle skipTimerFill
    call drawRectangle

skipTimerFill:
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
include "attacks.asm"

END start
