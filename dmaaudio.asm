; ==============================================================================
; dmaaudio.asm - TASM 4.1 Bulletproof Streaming Audio
; Uses DMA (Direct Memory Access) and IRQ interrupts for background playback.
; ==============================================================================

DATASEG
    audioFileHandle  dw 0
    currentAudioName dw 0    ; Saves the file name for re-opening if 'showbmp' steals the handle
    audioBufferSeg   dw 0
    audioBufferOff   dw 0
    oldIRQSeg        dw 0
    oldIRQOff        dw 0
    activeHalf       db 0    ; Tracks which half of the DMA buffer to fill next
    needsFill        db 0    ; Flag set by IRQ to trigger a buffer refill
    
    bufSize          equ 8192 ; Total DMA buffer size
    halfSize         equ 4096 ; Half-size for ping-pong buffering

CODESEG

; ------------------------------------------------------------------------------
; Send a command byte to the Sound Blaster DSP (Port 22Ch)
; ------------------------------------------------------------------------------
proc writeDSP
    push dx
    push ax
    mov dx, 22Ch
wait_write:
    in al, dx
    test al, 80h
    jnz wait_write           ; Wait until DSP is ready to accept commands
    pop ax
    out dx, al
    pop dx
    ret
endp writeDSP

; ------------------------------------------------------------------------------
; Allocate memory for the audio buffer and align it to a 4KB boundary
; ------------------------------------------------------------------------------
proc initAudioSystem
    mov ah, 48h
    mov bx, 1024             ; Request 16KB (1024 paragraphs)
    int 21h
    mov [audioBufferSeg], ax
    mov [audioBufferOff], 0

    ; Ensure 4KB alignment (Required for DMA to not cross page boundaries)
    xor eax, eax
    mov ax, [audioBufferSeg]
    shl eax, 4
    mov ebx, eax
    add ebx, 8191
    shr eax, 16
    shr ebx, 16
    cmp eax, ebx
    je safe_aligned

    xor eax, eax
    mov ax, [audioBufferSeg]
    shl eax, 4
    and eax, 0FFFFh
    mov edx, 10000h
    sub edx, eax
    mov [audioBufferOff], dx
safe_aligned:
    ret
endp initAudioSystem

; ------------------------------------------------------------------------------
; Sound Blaster Interrupt Handler (IRQ)
; Triggers whenever the DMA finishes playing a half-buffer
; ------------------------------------------------------------------------------
proc sb_irq_handler
    push ax
    push dx
    push ds

    mov ax, @data
    mov ds, ax

    mov dx, 22Eh             ; Acknowledge the interrupt to the DSP
    in al, dx

    mov al, 20h              ; Send EOI (End Of Interrupt) to PIC
    out 20h, al

    xor [activeHalf], 1      ; Flip the ping-pong buffer flag
    mov [needsFill], 1       ; Signal the main loop to fill the empty half

    pop ds
    pop dx
    pop ax
    iret
endp sb_irq_handler

; ------------------------------------------------------------------------------
; Open an audio file and initialize DMA transfer
; ------------------------------------------------------------------------------
proc playStreamingAudio
    mov [currentAudioName], dx

    ; Cleanup any currently playing audio
    call stopStreamingAudio

    ; Open File
    mov ax, 3D00h
    mov dx, [currentAudioName]
    int 21h
    mov [audioFileHandle], ax

    ; Pre-fill buffer with initial data
    mov bx, [audioFileHandle]
    mov dx, [audioBufferOff]
    mov cx, bufSize
    push ds
    mov ds, [audioBufferSeg]
    mov ah, 3Fh
    int 21h
    pop ds

    ; Hook the IRQ interrupt
    mov ax, 350Fh
    int 21h
    mov [oldIRQSeg], es
    mov [oldIRQOff], bx

    cli                      ; Disable interrupts while hooking
    push ds
    mov ax, cs
    mov ds, ax
    mov dx, offset sb_irq_handler
    mov ax, 250Fh
    int 21h
    pop ds
    sti                      ; Re-enable interrupts

    ; Enable Sound Blaster IRQ
    in al, 21h
    and al, 07Fh
    out 21h, al

    ; Setup DMA Channel 1 for transfer
    mov dx, 0Ah
    mov al, 05h              ; Mask DMA channel 1
    out dx, al

    mov dx, 0Ch
    mov al, 00h              ; Reset DMA flip-flop
    out dx, al

    mov dx, 0Bh
    mov al, 59h              ; Mode: Single, Write, Ch 1
    out dx, al

    ; Set DMA Memory Address
    xor eax, eax
    mov ax, [audioBufferSeg]
    shl eax, 4
    xor ebx, ebx
    mov bx, [audioBufferOff]
    add eax, ebx
    mov dx, 02h
    out dx, al
    mov al, ah
    out dx, al
    shr eax, 16
    mov dx, 83h
    out dx, al

    ; Set DMA Transfer Count
    mov ax, bufSize
    dec ax
    mov dx, 03h
    out dx, al
    mov al, ah
    out dx, al

    mov dx, 0Ah
    mov al, 01h              ; Unmask DMA channel 1
    out dx, al

    ; Initialize DSP
    mov al, 0D1h
    call writeDSP
    mov al, 40h
    call writeDSP
    mov al, 131              ; Frequency setting (Adjustable)
    call writeDSP
    
    mov al, 48h              ; Set Block Size
    call writeDSP
    mov ax, halfSize
    dec ax
    call writeDSP
    mov al, ah
    call writeDSP

    mov al, 1Ch              ; Start 8-bit Auto-Init DMA Transfer
    call writeDSP

    ret
endp playStreamingAudio

; ------------------------------------------------------------------------------
; Called every frame to keep the audio buffer topped up
; ------------------------------------------------------------------------------
proc pollAudio
    cmp [audioFileHandle], 0
    je @done
    pusha                    ; Protect main game math
    
    cmp [needsFill], 1
    jne pollDone
    mov [needsFill], 0

    ; Calculate memory offset for the inactive buffer half
    xor bx, bx
    mov bl, [activeHalf]
    xor bx, 1
    mov ax, halfSize
    mul bx
    add ax, [audioBufferOff]
    mov dx, ax

    mov bx, [audioFileHandle]
    mov cx, halfSize

    ; Read next chunk from file
    push ds
    mov ds, [audioBufferSeg]
    mov ah, 3Fh
    int 21h
    pop ds

    jc file_error            ; Self-Healing: If file was stolen, recover

    cmp ax, halfSize
    je pollDone              ; Successfully filled chunk

    ; If we reached end of file, restart file playback
    push ax
    mov ax, 4200h
    mov bx, [audioFileHandle]
    xor cx, cx
    xor dx, dx
    int 21h
    pop ax

    ; Fill remainder of buffer from the start of the file
    mov cx, halfSize
    sub cx, ax
    xor dx, dx
    mov dl, [activeHalf]
    xor dx, 1
    push ax
    mov ax, halfSize
    mul dx
    pop dx
    add ax, dx
    add ax, [audioBufferOff]
    mov dx, ax
    mov bx, [audioFileHandle]
    push ds
    mov ds, [audioBufferSeg]
    mov ah, 3Fh
    int 21h
    pop ds
    jmp pollDone

file_error:
    mov ax, 3D00h
    mov dx, [currentAudioName]
    int 21h
    mov [audioFileHandle], ax

pollDone:
    popa
@done:
    ret
endp pollAudio

; ------------------------------------------------------------------------------
; Stop all audio and close file handles
; ------------------------------------------------------------------------------
proc stopStreamingAudio
    cmp [audioFileHandle], 0
    je skipStop

    mov al, 0DAh             ; DMA Stop
    call writeDSP
    mov al, 0D3h             ; DSP Stop
    call writeDSP

    mov ah, 3Eh              ; Close file
    mov bx, [audioFileHandle]
    int 21h
    
    mov [audioFileHandle], 0
    mov [needsFill], 0
skipStop:
    ret
endp stopStreamingAudio