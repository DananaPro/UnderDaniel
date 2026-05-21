; ========================================================
; dmaaudio.asm - TASM 4.1 Bulletproof Streaming Audio
; ========================================================

DATASEG
    audioFileHandle  dw 0
    currentAudioName dw 0    ; Saves the file name for recovery
    audioBufferSeg   dw 0
    audioBufferOff   dw 0
    oldIRQSeg        dw 0
    oldIRQOff        dw 0
    activeHalf       db 0  
    needsFill        db 0  
    
    bufSize          equ 8192 
    halfSize         equ 4096 

CODESEG

proc writeDSP
    push dx
    push ax
    mov dx, 22Ch
wait_write:
    in al, dx
    test al, 80h
    jnz wait_write
    pop ax
    out dx, al
    pop dx
    ret
endp writeDSP

proc initAudioSystem
    mov ah, 48h
    mov bx, 1024      
    int 21h
    mov [audioBufferSeg], ax
    mov [audioBufferOff], 0

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

proc sb_irq_handler
    push ax
    push dx
    push ds

    mov ax, @data
    mov ds, ax

    mov dx, 22Eh
    in al, dx

    mov al, 20h
    out 20h, al

    xor [activeHalf], 1
    mov [needsFill], 1

    pop ds
    pop dx
    pop ax
    iret
endp sb_irq_handler

proc playStreamingAudio
    mov [currentAudioName], dx  

    ; --- PROPER CLEANUP ---
    ; Only stop the specific audio handle, do NOT sweep-close all handles
    call stopStreamingAudio 

    ; ---------------------------------------------------------------

    mov ax, 3D00h
    mov dx, [currentAudioName]
    int 21h
    mov [audioFileHandle], ax

    mov bx, [audioFileHandle]
    mov dx, [audioBufferOff]
    mov cx, bufSize
    
    push ds
    mov ds, [audioBufferSeg]
    mov ah, 3Fh
    int 21h
    pop ds

    mov ax, 350Fh
    int 21h
    mov [oldIRQSeg], es
    mov [oldIRQOff], bx

    cli                 ; Lock CPU to prevent crash while hooking
    push ds
    mov ax, cs
    mov ds, ax
    mov dx, offset sb_irq_handler
    mov ax, 250Fh
    int 21h
    pop ds
    sti                 ; Unlock CPU

    in al, 21h
    and al, 07Fh
    out 21h, al

    mov dx, 0Ah
    mov al, 05h
    out dx, al

    mov dx, 0Ch
    mov al, 00h
    out dx, al

    mov dx, 0Bh
    mov al, 59h       
    out dx, al

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

    mov ax, bufSize
    dec ax
    mov dx, 03h
    out dx, al
    mov al, ah
    out dx, al

    mov dx, 0Ah
    mov al, 01h
    out dx, al

    mov al, 0D1h      
    call writeDSP
    mov al, 40h       
    call writeDSP
    mov al, 131       
    call writeDSP
    
    mov al, 48h       
    call writeDSP
    mov ax, halfSize
    dec ax            
    call writeDSP
    mov al, ah
    call writeDSP

    mov al, 1Ch       
    call writeDSP

    ret
endp playStreamingAudio

proc pollAudio
    ; If no file is playing, return immediately to keep the loop moving
    cmp [audioFileHandle], 0
    je @done
    pusha                 ; Protect the main game's math from corruption!
    
    cmp [needsFill], 1
    jne pollDone
    mov [needsFill], 0

    xor bx, bx
    mov bl, [activeHalf]
    xor bx, 1
    mov ax, halfSize
    mul bx
    add ax, [audioBufferOff]
    mov dx, ax        

    mov bx, [audioFileHandle]
    mov cx, halfSize

    push ds
    mov ds, [audioBufferSeg]
    mov ah, 3Fh
    int 21h
    pop ds

    jc file_error         ; If showbmp closed our file, jump to recovery!

    cmp ax, halfSize
    je pollDone

    push ax           
    mov ax, 4200h
    mov bx, [audioFileHandle]
    xor cx, cx
    xor dx, dx
    int 21h

    pop ax
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
    ; Self-Healing: Re-open the file silently if it was stolen by showbmp
    mov ax, 3D00h
    mov dx, [currentAudioName]
    int 21h
    mov [audioFileHandle], ax

pollDone:
    popa
@done:
    ret
endp pollAudio

proc stopStreamingAudio
    cmp [audioFileHandle], 0
    je skipStop

    mov al, 0DAh
    call writeDSP
    mov al, 0D3h
    call writeDSP

    ; --------------------------------------------------------
    ; WE DELETED THE 'cli' TO 'sti' UNHOOKING BLOCK HERE!
    ; We must leave the handler attached so it safely absorbs
    ; the final delayed interrupt from the Sound Blaster.
    ; --------------------------------------------------------

    mov ah, 3Eh
    mov bx, [audioFileHandle]
    int 21h
    
    mov [audioFileHandle], 0
    mov [needsFill], 0      ; Clear any pending buffer fills!
skipStop:
    ret
endp stopStreamingAudio