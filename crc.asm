
SYS_READ    equ 0
SYS_WRITE   equ 1
SYS_OPEN    equ 2
SYS_CLOSE   equ 3
SYS_LSEEK   equ 8
SYS_EXIT    equ 60
STD_OUT     equ 1

section .bss
buffer:         resb 65550 ; Buffer of 65550 bytes.
poly_len:       resb 1     ; Length of the polynomial without the most significant bit.
buffer_end:     resd 1     ; Length of the read data in the buffer.
data:           resb 65550 ; Additional buffer for data.
buffer_pos:     resd 1     ; Current position in the buffer.
file_descriptor:resq 1     ; File descriptor.
jump_buffer:    resb 4     ; Buffer for the offset.
data_len:       resq 1     ; Length of the data.
polynomial:     resq 1     ; CRC polynomial.
control_sum:    resb 64    ; Here will be the result of the program.

section .rodata
BUFFER_LEN  equ poly_len - buffer ; Buffer length.

section .text
    global _start

_start:
    ; Check the validity of the arguments.
    mov al, byte [rsp] ; Load the number of arguments.
    cmp al, 3 ; Check if there are exactly 3 arguments
    ; (program name, file, polynomial)

    jne error ; If not, an error.
    mov r8, [rsp + 16] ; In r8, we save the pointer to the file name.
    mov r9, [rsp + 24] ; In r9, we save the pointer to the CRC polynomial.

    xor rcx, rcx ; Clear the counter.
    xor r15, r15 ; r15 will hold the CRC polynomial.
    test rsp, 15 ; Check if the stack is aligned to 16 bytes.
    jz validate_polynomial ; If yes, we read the polynomial.
    and rsp, -16 ; Align the stack to 16 bytes.

; Check if the polynomial is valid and load it into r15 if it is.
validate_polynomial: 
    mov al, byte [r9 + rcx] ; Load the next byte of the polynomial.
    inc rcx ; Increase the counter.
    test al, al ; Check if it's the end of the polynomial (zero byte).
    jz open_file ; If yes, the polynomial is valid.

    cmp rcx, 64 ; Check if we loaded more than 64 bytes of the polynomial.
    ja error ; If yes, an error because the polynomial is too long.

    cmp al, '0' ; Check if it's 0.
    je current_zero

    cmp rax, '1' ; Check if it's 1.
    je current_one

    jmp error ; Otherwise, an error.

current_zero: ; If the loaded byte is 0
    shl r15, 1 ; Shift the polynomial left by 1 and append a zero.
    jmp validate_polynomial ; Load the next byte of the polynomial.

current_one: ; If the loaded byte is 1
    shl r15, 1 ; Shift the polynomial left by 1 and append a zero.
    or r15, 1 ; Set the least significant bit to 1.
    jmp validate_polynomial ; Load the next byte of the polynomial.

open_file: ; Open the file.
    mov [rel polynomial], r15 ; Save the CRC polynomial.
    xor r15, r15 ; From now on, r15 will be our temporary register for checksum calculation.
    dec cl ; Decrease the counter because we loaded the zero byte.
    test cl, cl ; Check if the polynomial is empty.
    jz error ; If yes, an error.
    mov [rel poly_len], cl ; Save the polynomial length.

    mov rax, SYS_OPEN
    mov rdi, r8 ; File name.
    mov rsi, 0 ; Read-only.
    syscall

    test rax, rax ; Check if opening succeeded.
    js error ; If not, an error.

    mov rdi, rax ; Save the file descriptor in rdi.
    mov [rel file_descriptor], rdi ; Save the file descriptor.
    call read_file
    jmp read_data_length

read_file: ; Read data from the file.
    mov rax, SYS_READ 
    lea rsi, [rel buffer] 
    mov rdi, [rel file_descriptor] 
    mov rdx, BUFFER_LEN 
    syscall

    test rax, rax ; Check if the read was successful.
    js error ; If not, an error.
    jz error ; If 0 bytes were read, it's an error.
    mov [rel buffer_end], eax ; Save the length of the read data in rax.
    ret

read_data_length: ; Read the length of the data from the buffer.
    lea r12, [rel buffer] ; Save the pointer to the start of the buffer in r12.
    mov r13d, [rel buffer_pos] 
    xor rbx, rbx
    mov bl, byte [r12 + r13] ; Load the lower bits of the data length.
    inc dword [rel buffer_pos] ; Increase the buffer position.
    inc r13; Increase the buffer position.
    cmp r13d, [rel buffer_end] ; Check if the buffer is empty.
    jb read_data_length2 ; If not, load the data.
    xor r13, r13; Reset the buffer position if the buffer is empty.
    mov [rel buffer_pos], r13d ; Save the buffer position.
    call read_file ; If yes, load the next segment.

read_data_length2: ; Load the higher bits of the data length.
    movzx r14, bx ; Save the data length in fragment in r14.
    mov bl, byte [r12 + r13] ; Load the higher bits of the data length.
    shl bx, 8 ; Shift the higher bits left.
    add bx, r14w ; Add the lower bits of the data length.
    ; Now bx contains the data length in the fragment in big-endian NKB.
    movzx r14, bx
    mov [rel data_len], r14 ; Save the data length in the variable data_len.
    inc dword [rel buffer_pos] ; Increase the buffer position.

read_data: ; Read data from the current segment. May need to read the next segment.
    xor r10, r10 ; Clear the counter.
    lea r8, [rel data] ; Save the pointer to the data buffer in r8.
    lea r9, [rel buffer] ; Save the pointer to the buffer in r9.
    mov r13d, [rel buffer_pos] ; Save the buffer position in r13.
    movzx rdx, bx ; Save the data length in fragment in rdx.
    add edx, [rel buffer_pos] ; Add the data length in fragment to the buffer position.
    xor rcx, rcx ; Clear the counter.
    cmp edx, [rel buffer_end] ; Check if the data fits in the buffer.
    jb copy_data ; If yes, load the data.
    ; If not, the data does not fit in the buffer and the file needs to be read again.

read_loop: ; Copy the first segment to the data buffer
    mov al, [r9 + r13] ; Load the data.
    mov [r8 + r10], al ; Save the data.
    inc r10 ; Increase the counter.
    inc r13 ; Increase the buffer position.
    cmp r13d, [rel buffer_end] ; Check if the buffer is empty.
    jb read_loop ; If not, load the next data.
    call read_file ; Load the next segment.

    movzx rbx, bx ; Save the data length in fragment in rbx.
    sub rbx, r10 ; Subtract the loaded data from the data length in fragment.
    add r8, r10 ; Move the data pointer.
    xor r13, r13 ; Clear the buffer position.
    mov [rel buffer_pos], r13d ; Save the buffer position.
    xor rcx, rcx ; Clear the counter.
    ; Now in r8, we have the pointer to the free space in the data,
    ; where we will write the next part of the data.

copy_data: ; Copy the data from the segment to the data buffer.
    test rbx, rbx ; Check if the data is empty.
    jz read_jump ; If yes, load the offset.
copy_data_loop:
    mov al, [r9 + r13] ; Load the data.
    mov [r8 + rcx], al ; Save the data.
    inc rcx ; Increase the counter.
    inc r13 ; Increase the buffer position.
    cmp rcx, rbx ; Check if all data in the fragment is loaded.
    jb copy_data_loop ; If not, load the next data.
    mov [rel buffer_pos], r13d ; Save the buffer position.  
calculate_crc:
    ; The calculation of the checksum is as follows:
    ; 1. The r15 register is used to store the data bit by bit
    ;    from the right, shifting left with each bit.
    ; We will store the CRC polynomial (without the most significant bit)
    ;    in r12, shifted left by the necessary amount so that it's aligned
    ;    to the left side of r12.
    ; The r10b register will store the length of the CRC polynomial in r12.
    ; 2. If there is a carry in r15 (meaning the most significant bit was 1),
    ;    we perform a XOR operation with r12 (the CRC polynomial).
    ; 3. We repeat the operation for all the bits in the data.
    ; 4. At the end of the program, when the data is finished,
    ;    we perform a shift left 64 - poly_len times, checking for a carry after each shift,
    ;    and if there is a carry, we XOR.
    ; 5. In the end, r15 contains the checksum.

    mov r10b, [rel poly_len] 
    mov r12, [rel polynomial] 
    mov cl, 64 ; The maximum length of the CRC polynomial.
    sub cl, r10b ; Subtract the length of the CRC polynomial from 64.
    shl r12, cl ; Align the CRC polynomial to the left side of r12.
    mov rcx, [rel data_len] ; Length of the data.
    test rcx, rcx ; Check if the data is empty.
    jz read_jump ; If so, read the offset.

    lea r8, [rel data] ; r8 stores the pointer to the data.
    xor r11, r11 ; r11 points to the first byte of data.
    mov bl, 8 ; Store 8 in bl, as there are 8 bits in a byte.
    mov al, [r8 + r11] ; Load the first byte of data.

calculate_crc_loop: ; The loop that calculates the checksum.
    test bl, bl ; Check if there are no more bits in the byte.
    jz next_byte ; If so, load the next byte.
    shl al, 1 ; Shift the bits to the left.
    rcl r15, 1 ; Insert a bit into r15 and perform a shift left.
    jnc post_xor ; If there was no carry, no XOR is performed.
    xor r15, r12 ; Perform XOR with the CRC polynomial.

post_xor: ; After XOR (or no carry).
    dec bl ; Decrease the bit counter in the byte.
    jmp calculate_crc_loop

next_byte:
    inc r11 ; Increment the data pointer.
    cmp r11, rcx ; Check if all data has been processed.
    je read_jump ; If so, read the offset.
    mov bl, 8 ; Store 8 in bl, as there are 8 bits in a byte.
    mov al, [r8 + r11] ; Load the next byte of data.
    jmp calculate_crc_loop

read_jump: ; Read the offset in the current fragment.
    lea r8, [rel jump_buffer] ; r8 stores the pointer to the jump buffer.
    xor r14, r14
    mov eax, [rel buffer_end] ; Store the buffer length in rax.
    sub rax, r13 ; Store the number of bytes not yet read from the buffer.
    cmp rax, 4 ; Check if the offset fits in the buffer.
    jae save_jump2 ; If so, read the offset.
    ; If not, save the bytes that fit and re-read the file.

save_jump: ; Save subsequent offset bytes into the jump_buffer.
    mov [buffer_pos], r14d ; Zero out the buffer position.
    ; (this is needed for read_jump2)

    cmp rax, 0 ; Check if the buffer is empty.
    je read_jump2 ; If so, read the next fragment.
    mov bl, [r9 + r13] ; Load the offset byte.
    mov [r8 + r14], bl ; Save the offset byte.
    inc r14 ; Increment the offset byte index.
    inc r13 ; Increment the buffer position.
    dec rax ; Decrease the counter.
    jmp save_jump 

read_jump2: 
    call read_file ; Read the next fragment.

save_jump2: ; Save the offset into the jump_buffer.
    mov r13d, [rel buffer_pos] ; Store the buffer position in r13d.

; Save the offset in the jump_buffer, then in r14.
save_jump_loop: 
    mov bl, [r9 + r13] ; Load the offset byte from the buffer.
    mov [r8 + r14], bl ; Save the offset byte into the jump_buffer.
    inc r14 ; Increment the offset byte index.
    inc r13 ; Increment the buffer position.
    cmp r14, 4 ; Check if we've read 4 offset bytes.
    jb save_jump_loop ; If not, load the next offset bytes.
    mov r14d, dword [rel jump_buffer] ; Store the offset in r14.
    movsxd r14, r14d ; Store the offset in 64 bits in r14.
    mov [rel buffer_pos], r13d ; Save the buffer position.

jump_next: ; Perform the jump to the next fragment.

    mov rdx, [rel data_len] ; Store the data length in rdx.
    neg rdx
    sub rdx, 6 ; Subtract 6 bytes (2 bytes for data length and 4 bytes for the offset).
    cmp r14, rdx ; Check if the offset refers to itself.
    je end ; If so, this is the last fragment.

    add r13d, r14d ; Add the offset to the buffer position.
    jo jump_out_of_buffer ; If overflow occurs, re-read the file.
    cmp r13d, [rel buffer_end] ; Check if the offset is within the upper bounds of the buffer.
    jae jump_out_of_buffer ; If not, re-read the file.
    cmp r13, 0 ; Check if the offset is within the lower bounds of the buffer.
    jl jump_out_of_buffer ; If not, re-read the file.
    mov [rel buffer_pos], r13d ; Save the buffer position.
    jmp read_data_length ; If not, read the data length of the next fragment.

jump_out_of_buffer: ; The offset is outside the buffer.
    mov r13d, [rel buffer_pos] ; Store the buffer position in r13.
    xor rax, rax
    mov eax, [rel buffer_end] ; Store the buffer length in rax.
    sub rax, r13 ; Subtract the buffer position from the buffer length.
    sub r14, rax ; Subtract the buffer length from the offset.
    mov rax, SYS_LSEEK
    mov rdi, [rel file_descriptor]
    mov rsi, r14 ; The offset.
    mov rdx, 1 ; From where to move.
    syscall
    test rax, rax ; Check if the offset operation succeeded.
    js error ; If not, it's an error.
    call read_file ; Read the next fragment.
    xor r13, r13 ; Zero out the buffer position.
    mov [rel buffer_pos], r13d ; Save position 0 in the buffer.
    jmp read_data_length ; Read the data length of the next fragment.

end: ; End of the program.
    ; Finalize calculating the checksum from r15.
    mov r10b, [rel poly_len] ; Length of the CRC polynomial.
    mov r12, [rel polynomial] ; CRC polynomial.
    mov cl, 64 ; Maximum length of the CRC polynomial.
    sub cl, r10b ; Subtract the length of the CRC polynomial from 64.
    shl r12, cl ; Align the CRC polynomial to the left side of r12.
    mov cl, 64 ; Counter for how many times to shift left.
control_sum_loop: ; Loop calculating the checksum.
    test cl, cl
    jz save_crc
    shl r15, 1 ; Shift the bits to the left.
    jnc control_sum_post_xor ; If there was no carry, no XOR is performed.
    xor r15, r12 ; Perform XOR with the CRC polynomial.

control_sum_post_xor: ; After XOR (or no carry).
    dec cl ; Decrease the counter.
    jmp control_sum_loop

save_crc: ; Save the checksum.
    lea rax, [rel control_sum]
    xor rcx, rcx
save_crc_loop:
    test r10b, r10b
    jz write_result
    dec r10b
    shl r15, 1
    jc carry_flag
    mov byte [rax + rcx], '0'
    inc rcx
    jmp save_crc_loop

carry_flag:
    mov byte [rax + rcx], '1'
    inc rcx
    jmp save_crc_loop
write_result:
    mov byte [rax + rcx], 10 ; Newline character.
    inc rcx ; Number of bytes in the checksum.
    mov rax, SYS_WRITE 
    mov rdi, STD_OUT 
    lea rsi, [rel control_sum] ; The checksum.
    mov rdx, rcx ; Length of the checksum.
    syscall
    test rax, rax ; Check if the write operation succeeded.
    js error ; If not, it's an error.
    ; If successful, close the file and end the program.
    jz error ; If 0 bytes were written, it's an error.

    mov rax, SYS_CLOSE 
    mov rdi, [rel file_descriptor]
    syscall
    test rax, rax ; Check if the file was successfully closed.
    js exit

    mov rax, SYS_EXIT 
    xor rdi, rdi ; Exit code 0.
    syscall

error: ; Close the file because an error occurred.
    mov rax, SYS_CLOSE 
    mov rdi, [file_descriptor] 
    syscall
    
exit: ; Exit the program.
    mov rax, SYS_EXIT 
    mov rdi, 1 ; Error code.
    syscall
