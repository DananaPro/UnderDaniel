jumps   ; allow unbounded jumps (automatically converts out-of-range short jumps to near jumps)
include macros.asm
include graphmac.asm

IDEAL
P386          
MODEL small
STACK 1000h

DATASEG
; ==============================================================================
; Graphic Data Arrays
; ==============================================================================
include "bowl.asm"    ; character drawing data (bowl/heart sprite)
include "bowlM.asm"   ; character mask data (for transparency)

; ==============================================================================
; Math & Random Number Variables
; ==============================================================================
divisorTable    db 100, 10, 1, 0    ; Used for dividing values to print multi-digit numbers
COUNTER         db 0                ; General purpose counter
CEED            dw 0                ; Random seed value for RNG
RANDNUM         dw 0                ; Stores the generated random number

; ==============================================================================
; Shape & Drawing Variables (General purpose for drawing rectangles/UI)
; ==============================================================================
x               dw 0    
y               dw 0    
color           db 0    
wid             dw 0    
height          dw 0    

; ==============================================================================
; Player (Bowl/Heart) Variables
; ==============================================================================
bowlX           dw 140      ; Current X coordinate of the player (starts near center)
bowlY           dw 100      ; Current Y coordinate of the player
bowlPos         dw 32140    ; Pre-calculated screen memory offset (Y * 320 + X)

itemX           dw 140      ; Previous X coordinate (used to erase the old sprite before drawing new)
itemY           dw 100      ; Previous Y coordinate
itemPos         dw 32140    ; Previous screen memory offset

bowlwid         equ 16      ; Heart sprite width is 16 pixels
itemwid         dw  16      ; Variable width for items
itemh           dw  16      ; Variable height for items
bowlclr         db  40      ; Base color for the bowl/heart
maskOff         dw  ?       ; Offset for the transparency mask in memory
itemOff         dw  ?       ; Offset for the sprite data in memory

isFreezing      db 0        ; Game State Flag: 0 = Normal Gameplay, 1 = Stop all movement/logic immediately

hp              db 20       ; Player's current Health Points
points          db 0        ; Player's score/points

; ==============================================================================
; Controls & Boundaries (Keyboard Scan Codes and Screen Limits)
; ==============================================================================
leftdwn         equ 4Bh     ; Left Arrow Scan Code
rightdwn        equ 4Dh     ; Right Arrow Scan Code
updwn           equ 48h     ; Up Arrow Scan Code
downdwn         equ 50h     ; Down Arrow Scan Code
escKey          equ 01h     ; ESC Key Scan Code
enterKey        equ 0Dh     ; Enter Key ASCII Code     

arenaMinX       dw 14       ; Leftmost boundary of the playable area
arenaMaxX       dw 310      ; Rightmost boundary (Screen is 320px wide)
arenaMinY       dw 14       ; Top boundary
arenaMaxY       dw 150      ; Bottom boundary (Leaves bottom 50px for UI/HUD)

; ==============================================================================
; Attack & Wave Variables
; ==============================================================================
waveTimer       dw 0        ; Ticks up to track how long the current wave/break has lasted
isBreak         db 0        ; Wave State: 0 = Attacking phase, 1 = Break/Rest phase
WAVE_LEVEL      db 10        ; Current wave number (Starts at 1)
BEST_WAVE       db 1        ; High score tracker for highest wave reached
CHECKPOINT      db 1        ; Saves progress (e.g., checkpoint at wave 12 boss)
STORY_STATE     db 0        ; Tracks story progression: 1 = Pre-Boss cutscene room, 2 = Post-Boss room  

MAX_BULLETS     equ 12      ; Maximum number of bullets per side (Increased to 12 for boss chaos)
bulletWid       equ 7       ; Width of the bullet sprite

; Bullet arrays tracking X, Y, and Delay timers for all 4 directions
bulX            dw MAX_BULLETS dup (0)  ; Downward bullets X
bulY            dw MAX_BULLETS dup (0)  ; Downward bullets Y
bulDelay        dw MAX_BULLETS dup (0)

upBulX          dw MAX_BULLETS dup (0)
upBulY          dw MAX_BULLETS dup (0)
upBulDelay      dw MAX_BULLETS dup (0)

leftBulX        dw MAX_BULLETS dup (0)
leftBulY        dw MAX_BULLETS dup (0)
leftBulDelay    dw MAX_BULLETS dup (0)

rightBulX       dw MAX_BULLETS dup (0)
rightBulY       dw MAX_BULLETS dup (0)
rightBulDelay   dw MAX_BULLETS dup (0)

; Active counters for how many bullets are currently alive in each direction
activeDown      dw 0   
activeUp        dw 0    
activeLeft      dw 0
activeRight     dw 0

bulletX         dw 0        ; Temp variable used during collision & drawing calculations
bulletY         dw 0        ; Temp variable used during collision & drawing calculations
bulletSpeed     dw 2        ; Pixels to move per frame
oldHp           db 255      ; Used to track if HP changed (to avoid unnecessary redraws)
oldWave         db 255      ; Used to track if Wave changed

hpMsg           db 'HP: $'
ziltoidName     db 'ZILTOID', '$' ; Boss name string for UI display

; ==============================================================================
; File Names for Backgrounds & Cutscenes (Null-terminated for DOS APIs)
; ==============================================================================
startfile       db 'intro.bmp',0 
endfile         db 'gover2.bmp',0 
gamebg          db 'danbg.bmp',0
instfile        db 'lore.bmp',0
spookyFile      db 'spookyrm.bmp',0
spookyFile2     db 'spooky2.bmp',0
bossRmFile      db 'bossrm.bmp',0
bossBgFile      db 'bossbg.bmp',0
winFile         db 'win.bmp',0

; ==============================================================================
; Audio Variables (Raw audio files for streaming)
; ==============================================================================
menuSnd         db 'menu.raw',0
batlSnd         db 'batl.raw',0   
deadSnd         db 'dead.raw',0
bossSnd         db 'boss.raw',0  
winSnd          db 'win.raw',0
spokSnd         db 'spok.raw',0  ; Spooky Room 1
bmsgSnd         db 'bmsg.raw',0  ; Boss Dialogue
safeSnd         db 'safe.raw',0  ; Spooky Room 2 (Post-win)

baseSP          dw 0        ; Stores the original Stack Pointer for clean game resets
filehandle      dw ? 
currentFile     dw ? 

; Variables for reading and drawing 256-color BMP files
Header          db 54 dup (0)       ; BMP Header buffer
Palette         db 256*4 dup (0)    ; Color palette buffer (256 colors * 4 bytes/RGBA)
ScrLine         db 320 dup (0)      ; Buffer for reading one row of pixels at a time
ErrorMsg        db 'Error in open file$'
picHigh         dw ? 
picWidth        dw ? 
leftGap         dw ?  
topGap          dw ?  
place           dw ? 

CODESEG

start:
    ; --------------------------------------------------------------------------
    ; System Initialization
    ; --------------------------------------------------------------------------
    mov ah, 4Ah             ; DOS API: Modify memory allocation
    mov bx, 8192            ; Shrink memory footprint to make room for audio buffers  
    int 21h

	mov ax, 0B00h           ; AH=0Bh: BIOS Set Keyboard Beep Status
    mov bl, 0               ; BL=0: Disable keyboard beeps
    int 16h                 ; Call BIOS Keyboard Services

    setDS                   ; Macro to setup Data Segment            
    setES                   ; Macro to setup Extra Segment (Usually used for string ops or VGA memory)            

    call initAudioSystem    ; Initialize the DMA memory buffer ONCE at startup

    graphMod                ; Macro to enter VGA 320x200 256-color Mode (INT 10h, AH=00h, AL=13h)          

    ; --------------------------------------------------------------------------
    ; Main Menu & Setup
    ; --------------------------------------------------------------------------
    mov dx, offset menuSnd
    call playStreamingAudio ; Start Menu Music

    mov [currentFile], offset startfile
    call showbmp            ; Draw Intro screen

waitForStartKey:
    call pollAudio          ; Keep audio buffer full while waiting in menu

    mov ah, 01h             ; INT 16h, AH=01h: Check keyboard buffer (Non-blocking)
    int 16h
    jz waitForStartKey      ; If Zero Flag is set (no key pressed), loop back
    
    ; Key was pressed! Consume it from the buffer so it doesn't trigger again
    mov ah, 00h             ; INT 16h, AH=00h: Get keystroke
    int 16h
    
    cmp ah, escKey          ; Did player press ESC?
    je exitJ                ; Yes: Exit game

    cmp al, enterKey        ; Did player press Enter?
    je startGameImmediately ; Yes: Skip to game

    or al, 20h              ; Convert uppercase letter to lowercase (e.g. 'C' becomes 'c')
    cmp al, 'c'             ; Did player press 'C'?
    je displayLore          ; Yes: Show Lore screen

    jmp waitForStartKey     ; Invalid key, keep waiting

displayLore:
    mov [currentFile], offset instfile
    call showbmp            ; Draw Lore screen
    
waitForEnterFromLore:
    call pollAudio          ; Keep music streaming while reading lore

    mov ah, 01h             ; Check for key press
    int 16h
    jz waitForEnterFromLore

    mov ah, 00h             ; Consume key
    int 16h

    cmp ah, escKey          ; Allow exiting from the lore screen too
    je exitJ
    cmp al, enterKey        ; Wait until they press Enter to continue
    jne waitForEnterFromLore

startGameImmediately:
    mov [currentFile], offset gamebg
    call showbmp            ; Draw main gameplay background

    ; Switch to Battle Music
    mov dx, offset batlSnd
    call playStreamingAudio

gamestart:
    mov [isFreezing], 0     ; Ensure game is not paused
    mov [baseSP], sp        ; Save pristine stack pointer for hard-resets upon death
    call initGame           ; Initialize player/HUD
    
    ; Setup the very first wave of bullets
    call pickAttackPattern
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets

; ==============================================================================
; MAIN GAME LOOP - Runs continuously every frame
; ==============================================================================
mainLoop:   
    call pollAudio          ; 1. Keep music playing
    
    ; 2. Check Pause/Freeze State
    cmp [isFreezing], 1
    je checkInput           ; If frozen (cutscene), skip all logic and only allow input
    
    call delay              ; 3. Throttle game speed (INT 15h, AH=86h Wait)
    inc [waveTimer]         ; 4. Advance the game clock

    ; 5. Check which phase we are in (Attacking vs Break)
    cmp [isBreak], 1
    je handleBreak          ; Jump to break logic if currently resting

    ; --- ATTACK WAVE LOGIC ---
    ; 6. Move, draw, and check collisions for all active bullets
    call handleAllBullets  
    call handleAllUpBullets
    call handleAllLeftBullets
    call handleAllRightBullets
    
    call drawHealthBar      ; 7. Update HUD
    
    ; 8. Check Wave Timer
    cmp [waveTimer], 420    ; Has the wave lasted 420 ticks? (Approx 7 Seconds)
    jl checkInput           ; No: continue to input checking
    
    ; --- WAVE END LOGIC ---
    mov [isBreak], 1        ; Switch state to Break Time
    mov [waveTimer], 0      ; Reset clock for the break countdown
    
    ; Clean the screen of all current bullets
    call eraseAllBullets
    call eraseAllUpBullets
    call eraseAllLeftBullets
    call eraseAllRightBullets
    inc [WAVE_LEVEL]        ; Progress to next level
	
    ; ---------------------------------------------------
    ; Post-Wave Healing Mechanism (Add 4 HP, cap at 20)
    ; ---------------------------------------------------
    mov al, [hp]
    add al, 4
    cmp al, 20
    jle @applyHeal
    mov al, 20              ; Clamp HP to max of 20
@applyHeal:
    mov [hp], al
    ; ---------------------------------------------------

    ; Check for Story Checkpoints based on Wave number
    cmp [WAVE_LEVEL], 11    ; Did we just beat Wave 10?
    je triggerSpooky1       ; Go to Pre-Boss room

    cmp [WAVE_LEVEL], 14    ; Did we just beat Wave 13 (Boss Part 2)?
    je triggerSpooky2       ; Go to Post-Boss room
    
    mov [isFreezing], 0     ; Ensure game continues normally if no story trigger
    jmp checkInput
    
triggerSpooky1:
    mov [isFreezing], 1     ; Stop game logic
    jmp goSpooky1           ; Jump to cutscene setup

triggerSpooky2:
    mov [isFreezing], 1
    jmp goSpooky2
    ; ---------------------------------

handleBreak:
    call drawHealthBar      ; Update HUD (Timer bar draws differently during breaks)
    
    cmp [waveTimer], 120    ; Has the break lasted 120 ticks? (Approx 2 seconds)
    jl checkInput           ; No: continue waiting

    ; --- BREAK END LOGIC ---
    mov [isBreak], 0        ; Back to Attack state
    mov [waveTimer], 0      ; Reset clock for attack wave
    
    ; Generate a new wave pattern and spawn new bullets
    call pickAttackPattern
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets
     
; ==============================================================================
; INPUT HANDLING - FLUSHING BUFFER TO PREVENT BEEPING
; ==============================================================================
checkInput:
    mov ah, 01h             ; Check if there is ANY key in the buffer
    int 16h
    jz mainLoop             ; If empty, proceed to next frame

flushBuffer:
    mov ah, 00h             ; Extract the oldest key from the buffer
    int 16h
    mov cx, ax              ; Save this key in CX
    
    mov ah, 01h             ; Peek: Is there another key behind it?
    int 16h
    jnz flushBuffer         ; If yes, loop back to discard the old one and get the new one

    ; The buffer is now empty. AX contains only the most recent key press.
    mov ax, cx              
    or al, 20h              ; Normalize to lowercase

    ; Process your movement keys
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

; Trampolines for jumps (since relative jumps have distance limits in 16-bit asm)
moveUpJ:    jmp doMoveUp
moveDownJ:  jmp doMoveDown
moveLeftJ:  jmp doMoveLeft
moveRightJ: jmp doMoveRight
exitJ:      jmp exit

; ==============================================================================
; MOVEMENT HANDLERS
; ==============================================================================
doMoveLeft:
    mov ax, [bowlX]
    sub ax, 5               ; Move 5 pixels left
    cmp ax, [arenaMinX]     ; Hit left wall?
    jl mainLoop             ; Yes: Cancel movement
    mov [itemX], ax         ; Save for erasing
    call movLeft            ; Execute drawing update
    jmp mainLoop

doMoveRight:
    mov ax, [bowlX]
    add ax, 5               ; Move 5 pixels right
    add ax, 16              ; Add sprite width to check right edge
    cmp ax, [arenaMaxX]     ; Hit right wall?
    jg mainLoop
    mov [itemX], ax
    call movRight
    jmp mainLoop

doMoveUp:
    mov ax, [bowlY]
    sub ax, 5               ; Move 5 pixels up
    cmp ax, [arenaMinY]     ; Hit top wall?
    jl mainLoop
    mov ax, [bowlX]
    mov [itemX], ax
    call movUp
    jmp mainLoop

doMoveDown:
    mov ax, [bowlY]
    add ax, 5               ; Move 5 pixels down
    add ax, 16              ; Add sprite height to check bottom edge
    cmp ax, [arenaMaxY]
    jg mainLoop
    mov ax, [bowlX]
    mov [itemX], ax
    call movDown
    jmp mainLoop

; ==============================================================================
; STORY TRANSITIONS & MINI-GAME (Spooky Rooms)
; ==============================================================================
goSpooky1:
    call stopStreamingAudio 
    mov dx, offset spokSnd          ; <--- LOAD SPOOKY 1 MUSIC
    call playStreamingAudio         ; <--- PLAY IT
    mov [STORY_STATE], 1
    mov [currentFile], offset spookyFile
    jmp setupSpookyRoom

goSpooky2:
    call stopStreamingAudio 
    mov dx, offset safeSnd          ; <--- LOAD SPOOKY 2 MUSIC
    call playStreamingAudio         ; <--- PLAY IT
    mov [STORY_STATE], 2
    mov [currentFile], offset spookyFile2
    jmp setupSpookyRoom

setupSpookyRoom:
    ; 1. Clear the old heart from the battle screen FIRST before swapping backgrounds
    call eraseBowl      

    ; 2. Load the spooky room background
    call showbmp        

    ; 3. Teleport player to the bottom center so they have room to walk UP to the door
    mov ax, 140
    mov [bowlX], ax
    mov [itemX], ax
    mov ax, 130
    mov [bowlY], ax
    mov [itemY], ax

    ; Recalculate linear memory offset (Y * 320 + X)
    mov ax, [bowlY]
    mov bx, 320
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax

    call drawBowl           ; Draw Heart in new position
    jmp spookyLoop          ; Enter independent movement loop

spookyLoop:
    call pollAudio          ; (Music might be stopped, but maintain buffer logic)
    
    mov ah, 01h             ; Check input
    int 16h
    jz spookyLoop

    mov ah, 00h             ; Extract key
    int 16h
    or al, 20h

    ; In the spooky room, you can only walk UP
    cmp ah, updwn
    je spookyMoveUp
    cmp al, 'w'
    je spookyMoveUp
    
    cmp ah, escKey
    je exitJ
    jmp spookyLoop          ; Ignore all other keys

spookyMoveUp:
    ; 1. Erase the old heart first by redrawing the whole background over it 
    ; (Inefficient but works for a slow cutscene without needing complex erase logic)
	call showbmp
	
    ; 2. Save previous position
    mov ax, [bowlX]
    mov [itemX], ax
    mov ax, [bowlY]
    mov [itemY], ax

    ; 3. Move up by 5 pixels
    sub ax, 5
    mov [bowlY], ax

    ; 4. Recalculate screen offset
    mov bx, 320
    mov dx, ax
    mul bx
    add ax, [bowlX]
    mov [bowlPos], ax
    mov [itemPos], ax

    ; 5. Draw new heart
    call drawBowl

    ; 6. CHECK IF AT DOOR (If Y <= 70, player has reached the door)
    cmp [bowlY], 70              
    jle spookyDoorReached   
    jmp spookyLoop

spookyDoorReached:
    cmp [STORY_STATE], 1    ; Are we at the mid-game boss door?
    je goBossDialogue
    cmp [STORY_STATE], 2    ; Are we at the final exit door?
    je goWinScreen

goBossDialogue:
    call stopStreamingAudio 
    mov dx, offset bmsgSnd          ; <--- LOAD BOSS DIALOGUE MUSIC
    call playStreamingAudio         ; <--- PLAY IT
    mov [WAVE_LEVEL], 12    ; Force the wave to 12 (Boss start)
    mov [hp], 20            ; Full heal before boss
    mov [isFreezing], 1     ; Ensure game loop logic is paused
    
    mov [currentFile], offset bossRmFile
    call showbmp            ; Show Boss warning/dialogue screen
    mov [CHECKPOINT], 12    ; Save checkpoint so dying on boss restarts at boss

waitBossKey:
    call pollAudio
    mov ah, 01h
    int 16h
    jz waitBossKey
    mov ah, 00h
    int 16h
    cmp al, enterKey        ; Wait for Enter to begin fight
    jne waitBossKey

    ; --- ENTER WAVE 12 (BOSS FIGHT) ---
    mov [currentFile], offset bossBgFile
    call showbmp            ; Load Boss Arena background
    
    mov dx, offset bossSnd
    call playStreamingAudio ; Start Boss Music

    ; Reset game state variables for Boss
    mov [isFreezing], 0     ; UNFREEZE logic to allow battle
    mov [isBreak], 0        ; Start immediately attacking
    mov [waveTimer], 0

    ; Setup player position (centered)
    mov ax, 140
    mov [bowlX], ax
    mov ax, 100
    mov [bowlY], ax

    ; Recalculate memory offsets
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

    ; Initialize Boss attacks
    call pickAttackPattern  ; This function detects WAVE 12 and forces Boss patterns
    call spawnAllBullets
    call spawnAllUpBullets
    call spawnAllLeftBullets
    call spawnAllRightBullets

    jmp mainLoop            ; Jump back to main loop to handle the fight

goWinScreen:
    mov dx, offset winSnd
    call playStreamingAudio ; Start Victory Music
    
    mov [currentFile], offset winFile
    call showbmp            ; Show End Screen

waitWinKey:
    call pollAudio
    mov ah, 01h
    int 16h
    jz waitWinKey
    mov ah, 00h
    int 16h
    cmp ah, escKey
    je exitJ
    cmp al, enterKey        ; Wait for Enter to restart game
    jne waitWinKey

    call stopStreamingAudio

    ; Hard Reset for a completely new game loop
    mov [CHECKPOINT], 1     
    mov [WAVE_LEVEL], 1
    mov [hp], 20       
    jmp startGameImmediately

; ==============================================================================
; GAME OVER & RESTART LOGIC
; ==============================================================================
gameOver:
    mov sp, [baseSP]        ; Restore pristine stack pointer to prevent stack overflow on death loop

    ; --- CHECK FOR NEW HIGH SCORE ---
    mov al, [WAVE_LEVEL]
    cmp al, [BEST_WAVE]
    jle skipHighScore       ; If current wave is LESS or EQUAL to best, skip updating
    mov [BEST_WAVE], al     ; NEW HIGH SCORE! Save it to BEST_WAVE
skipHighScore:

    mov dx, offset deadSnd
    call playStreamingAudio ; Start Game Over Music

    mov [currentFile], offset endfile
    call showbmp            ; Draw Game Over Screen

    ; -----------------------------------------
    ; Print Final Wave Score on Game Over Screen
    ; -----------------------------------------
    mov ah, 2               ; Set cursor position
    mov bh, 0               ; Video Page 0
    mov dh, 12              ; Row 12
    mov dl, 4               ; Column 4
    int 10h

    mov bl, 14              ; Text attribute (Yellow)
    
    ; Print "WAVES: " via INT 21h AH=2 (Print char in DL)
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

    ; Convert WAVE_LEVEL number to ASCII and print (Tens and Ones)
    xor ax, ax
    mov al, [WAVE_LEVEL]
    mov cl, 10          
    div cl                  ; AL = Tens digit, AH = Ones digit
    
    push ax                 ; Save remainder
    add al, '0'             ; Convert Tens to ASCII
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h                 ; Print Tens
    
    pop ax                  ; Restore remainder
    mov al, ah          
    add al, '0'             ; Convert Ones to ASCII
    mov dl, al
    mov bl, 14          
    mov ah, 2
    int 21h                 ; Print Ones

    ; -----------------------------------------
    ; Print BEST Wave Score 
    ; -----------------------------------------
    mov ah, 2               ; Set cursor position
    mov bh, 0
    mov dh, 14              ; Row 14 (Two lines exactly under the current score)
    mov dl, 4               ; Column 4
    int 10h

    mov bl, 14              ; Yellow text
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

    ; Convert BEST_WAVE number to ASCII and print
    xor ax, ax
    mov al, [BEST_WAVE]
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

waitForGameOverKey:
    call pollAudio          ; Keep streaming death music

    mov ah, 01h             ; Check input
    int 16h
    jz waitForGameOverKey 

    mov ah, 00h             ; Consume input
    int 16h

    cmp ah, escKey
    je exit
    cmp al, enterKey
    jne waitForGameOverKey
    
    ; --- RESTART LOGIC ---
    mov [hp], 20            ; Reset HP
    
    ; Load the Checkpoint instead of forcing Wave 1
    mov al, [CHECKPOINT]
    mov [WAVE_LEVEL], al
    
    mov [waveTimer], 0 
    mov [isBreak], 0   
    mov [oldHp], 255   
    mov [oldWave], 255 
    
    ; Did player die on the boss?
    cmp [CHECKPOINT], 12
    je goBossDialogue       ; Skip the game loop and teleport back to the dialogue room

    ; Otherwise, normal restart
    jmp startGameImmediately
    
    mov [currentFile], offset gamebg
    call showbmp
    jmp gamestart

exit:
    call stopStreamingAudio ; Cleanly stop DMA transfer and interrupts
    textmod                 ; Macro to return to DOS text mode (INT 10h, AX=0003h)
    mov ax, 4c00h           ; DOS API: Terminate Program
    int 21h

; ==============================================================================
; Game Procedures 
; ==============================================================================
proc initGame
    call drawBowl           ; Initial draw of the player
    ret
endp initGame

proc delay
    ; System wait function (1,000,000 = 1 second)
    mov ah, 86h             ; BIOS Wait Service
    mov cx, 0               ; High word of wait time (Microseconds)
    mov dx, 33333           ; Low word of wait time (~33ms, aiming for ~30 FPS)
    int 15h
    ret
endp delay

; ==============================================================================
; HUD Drawing Routine (Text and Visual Bars)
; ==============================================================================
proc drawHealthBar
    push ax bx dx

    ; -----------------------------------------
    ; 1. Print the Wave Counter
    ; -----------------------------------------
    mov ah, 2               ; Set cursor position
    mov bh, 0
    mov dh, 22              ; Row 22 (Perfectly aligned with HP text)
    mov dl, 27              ; Far right column
    int 10h

    ; Check if we should draw normal wave counter or boss name
    cmp [WAVE_LEVEL], 12
    jge @drawZiltoid        ; If Wave >= 12, display boss name instead

    ; --- NORMAL WAVE TEXT ---
    mov bl, 10              ; Light Green text attribute
    mov ah, 2               ; Print Character
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

    ; Print Wave Number
    xor ax, ax
    mov al, [WAVE_LEVEL]
    mov bl, 10          
    div bl                  ; Div by 10 to get Tens and Ones
    push ax             
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h                 ; Tens
    pop ax              
    mov al, ah          
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h                 ; Ones

    jmp @doneWaveText       ; Skip the boss text rendering

@drawZiltoid:
    ; --- BOSS WAVE TEXT ---
    mov dx, offset ziltoidName
    mov ah, 09h             ; Print string (ending in $)
    int 21h

@doneWaveText:

    ; -----------------------------------------
    ; 2. Print Current HP Text
    ; -----------------------------------------
    mov ah, 2               ; Set Cursor
    mov bh, 0
    mov dh, 22              ; Row 22
    mov dl, 2               ; Shifted far left so it doesn't hit the graphics bar
    int 10h

    ; Print numeric HP value
    xor ax, ax
    mov al, [hp]        
    mov bl, 10          
    div bl              
    push ax             
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h                 ; Print Tens
    pop ax              
    mov al, ah          
    add al, '0'         
    mov dl, al
    mov ah, 2
    int 21h                 ; Print Ones

    ; Print "/20 HP"
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
    ; 3. Draw the Visual Health Background (Empty Bar)
    ; -----------------------------------------
    mov [x], 100            ; X=100 so it sits nicely next to the text
    mov [y], 178            ; Y=178 centers the rectangle perfectly on Row 22 text
    mov [wid], 80           ; 80 pixels wide total
    mov [height], 5         ; 5 pixels tall
    mov [color], 8          ; Gray color for empty background
    call drawRectangle      ; Function to plot the solid block

    ; -----------------------------------------
    ; 4. Draw the Red Health Fill
    ; -----------------------------------------
    xor ax, ax
    mov al, [hp]
    cmp al, 0
    jle drawTimerSection    ; If dead/0 HP, skip drawing the red fill      
    
    mov bx, 4               ; Math: 20 HP * 4 pixels/HP = 80 pixels wide bar
    mul bx              
    mov [wid], ax           ; Set fill width dynamically based on HP
    mov [color], 63         ; Palette Color 63: Bright Red
    call drawRectangle

drawTimerSection:
    ; -----------------------------------------
    ; 5. Print "TIME" Text
    ; -----------------------------------------
    mov ah, 2               ; Set cursor
    mov bh, 0
    mov dh, 24              ; Row 24 (Sits exactly under HP text)
    mov dl, 2               ; Shifted far left
    int 10h

    mov bl, 10              ; Light Green

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
    ; 6. Draw Timer Bar Background (Empty Bar)
    ; -----------------------------------------
    mov [x], 100
    mov [y], 194            ; Y=194 centers it perfectly on Row 24 text
    mov [wid], 84           ; Total width of timer bar
    mov [height], 5
    mov [color], 8          ; Gray background
    call drawRectangle

    ; -----------------------------------------
    ; 7. Calculate & Draw Shrinking Timer Fill
    ; -----------------------------------------
    cmp [isBreak], 1
    je calcBreakTimer       ; Use different math for break phase

    ; -- Attack Phase -- 
    ; Timer goes 0 -> 420. We want a shrinking bar from 84px to 0px.
    mov ax, [waveTimer] 
    mov bl, 5               ; 420 / 5 = 84 (Max width)
    div bl              
    
    mov dl, 84
    sub dl, al              ; 84 - (current time scaled) = pixels remaining
    xor dh, dh
    mov [wid], dx
    mov [color], 63         ; Bright Red to perfectly match Health!
    jmp doTimerFill

calcBreakTimer:
    ; -- Break Phase -- 
    ; Break timer goes 0 -> 120. Shrink from 84px to 0px.
    mov ax, [waveTimer] 
    mov bx, 7
    mul bx                  ; Scale by 7/10
    mov bx, 10
    div bx              
    
    mov dx, 84
    sub dx, ax              ; Reverse it so the bar shrinks
    mov [wid], dx
    mov [color], 63         ; Red

doTimerFill:
    cmp [wid], 0
    jle skipTimerFill       ; Don't draw if width is <= 0
    call drawRectangle

skipTimerFill:
    pop dx bx ax
    ret
endp drawHealthBar

; ==============================================================================
; Include Procedures (External dependencies)
; ==============================================================================
; Note: In TASM, includes are placed at the bottom if they contain subroutines 
; to avoid "Undefined symbol" or premature code execution errors.
include "movproc.asm"       ; Movement logic
include "vidshap.asm"       ; Graphics drawing functions (drawRectangle, etc.)
include "bmpproc.asm"       ; BMP image parsing/drawing
include "fileproc.asm"      ; File handle management
include "numproc.asm"       ; Number to string conversions
include "movarrow.asm"      ; Specialized movement checks
include "dmaaudio.asm"      ; The sound blaster interrupt/buffer logic
include "attacks.asm"       ; Bullet spawning and collision mechanics

END start