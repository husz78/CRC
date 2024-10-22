SYS_READ equ 0
SYS_WRITE equ 1
SYS_OPEN equ 2
SYS_CLOSE equ 3
SYS_LSEEK equ 8
SYS_EXIT equ 60
STD_OUT equ 1

section .bss
buffer: resb 65550 ; Bufor o długości 65550 bajtów.
poly_len: resb 1 ; Długość wielomianu bez najbardziej znaczącego bitu.
buffer_end: resd 1 ; DŁugość odczytanych danych w buforze.
data: resb 65550 ; Bufor dodatkowy na dane.
buffer_pos: resd 1; Aktualna pozycja w buforze.
file_descriptor: resq 1 ; Deskryptor pliku.
jump_buffer: resb 4 ; Bufor na przesunięcie.
data_len: resq 1 ; Długość danych.
polynomial: resq 1 ; Wielomian crc.
control_sum: resb 64 ; Tu będzie wynik programu.


section .rodata
BUFFER_LEN equ poly_len - buffer ; Długość bufora.

section .text
    global _start

_start:
    ; Sprawdzamy poprawność argumentów.
    mov al, byte [rsp] ; Wczytujemy liczbę argumentów.
    cmp al, 3 ; Sprawdzamy, czy jest ich dokładnie 3 
    ; (nazwa programu, plik, wielomian)

    jne error ; Jeśli nie, to błąd.
    mov r8, [rsp + 16] ; W r8 zapisujemy wskaźnik na nazwę pliku.
    mov r9, [rsp + 24] ; W r9 zapisujemy wskaźnik na wielomian crc.

    xor rcx, rcx ; Zerujemy licznik.
    xor r15, r15 ; W r15 będziemy trzymać wielomian crc.
    test rsp, 15 ; Sprawdzamy, czy stos jest wyrównany do 16 bajtów.
    jz validate_polynomial ; Jeśli tak, to wczytujemy wielomian.
    and rsp, -16 ; Wyrównujemy stos do 16 bajtów.

; Sprawdzamy poprawność wielomianu i jak jest poprawny to wczytujemy do r15.
validate_polynomial: 
    mov al, byte [r9 + rcx] ; Wczytujemy kolejny bajt wielomianu.
    inc rcx ; Zwiększamy licznik.
    test al, al ; Sprawdzamy, czy to koniec wielomianu (bajt zerowy).
    jz open_file ; Jeśli tak, to wielomian jest poprawny.

    cmp rcx, 64 ; Sprawdzamy, czy wczytaliśmy więcej niż 64 bajty wielomianu.
    ja error ; Jeśli tak, to błąd, bo wielomian jest za długi.

    cmp al, '0' ; Sprawdzamy, czy to 0.
    je current_zero

    cmp rax, '1' ; Sprawdzamy, czy to 1.
    je current_one

    jmp error ; W przeciwnym wypadku błąd

current_zero: ; jesli wczytany bajt to 0
    shl r15, 1 ; Uzupełniamy wielomian zerem z lewej strony.
    jmp validate_polynomial ; Wczytujemy kolejny bajt wielomianu.

current_one: ; jesli wczytany bajt to 1
    shl r15, 1 ; Uzupełniamy wielomian zerem z lewej strony.
    or r15, 1 ; Ustawiamy najmniej znaczący bit na 1.
    jmp validate_polynomial ; Wczytujemy kolejny bajt wielomianu.

open_file:; Otwieramy plik.
    mov [rel polynomial], r15 ; Zapisujemy wielomian crc.
    xor r15, r15 ; Od tego momentu r15 będzie naszym rejestrem
    ; tymczasowym do obliczenia sumy kontrolnej.
    dec cl ; Zmniejszamy licznik, bo wczytaliśmy bajt zerowy.
    test cl, cl ; Sprawdzamy, czy wielomian jest pusty.
    jz error ; Jeśli tak, to błąd.
    mov [rel poly_len], cl ; Zapisujemy długość wielomianu.

    mov rax, SYS_OPEN
    mov rdi, r8 ; Nazwa pliku.
    mov rsi, 0 ; Odczyt.
    syscall

    test rax, rax ; Sprawdzamy, czy otwarcie się powiodło.
    js error ; Jeśli nie, to błąd.

    mov rdi, rax ; W rdi zapisujemy deskryptor pliku.
    mov [rel file_descriptor], rdi ; Zapisujemy deskryptor pliku.
    call read_file
    jmp read_data_length

read_file: ; Odczytujemy dane z pliku.
    mov rax, SYS_READ 
    lea rsi, [rel buffer] 
    mov rdi, [rel file_descriptor] 
    mov rdx, BUFFER_LEN 
    syscall

    test rax, rax ; Sprawdzamy, czy odczyt się powiódł.
    js error ; Jeśli nie, to błąd.
    jz error ; Jeśli odczytano 0 bajtów, to błąd.
    mov [rel buffer_end], eax ; W rax jest długość odczytanych danych.
    ret

read_data_length: ; Odczytujemy długość danych z bufora.
    lea r12, [rel buffer] ; W r12 zapisujemy wskaźnik na początek bufora.
    mov r13d, [rel buffer_pos] 
    xor rbx, rbx
    mov bl, byte [r12 + r13] ; Wczytujemy młodsze bity długości danych.
    inc dword [rel buffer_pos] ; Zwiększamy pozycję w buforze.
    inc r13; Zwiększamy pozycję w buforze.
    cmp r13d, [rel buffer_end] ; Sprawdzamy, czy skończył się bufor.
    jb read_data_length2 ; Jeśli nie, to wczytujemy dane.
    xor r13, r13; Zerujemy pozycję w buforze jeśli skończył się bufor.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję w buforze.
    call read_file ; Jeśli tak, to wczytujemy kolejny fragment.

read_data_length2: ; Wczytujemy starsze bity długości danych.
    movzx r14, bx ; W r14 zapisujemy długość danych w fragmencie.
    mov bl, byte [r12 + r13] ; Wczytujemy długość danych w fragmencie.
    shl bx, 8 ; Przesuwamy starsze bity długości danych.
    add bx, r14w ; Dodajemy młodsze bity długości danych.
    ; Teraz w bx mamy długość danych w fragmencie w big-endian NKB.
    movzx r14, bx
    mov [rel data_len], r14 ; Zapisujemy długość danych w zmiennej data_len.
    inc dword [rel buffer_pos] ; Zwiększamy pozycję w buforze.

read_data: ; Odczytujemy dane z danego fragmentu. Możliwe, że trzeba będzie wczytać kolejny fragment.
    xor r10, r10 ; Zerujemy licznik.
    lea r8, [rel data] ; W r8 zapisujemy wskaźnik na bufor danych.
    lea r9, [rel buffer] ; W r9 zapisujemy wskaźnik na bufor.
    mov r13d, [rel buffer_pos] ; W r13 zapisujemy pozycję w buforze.
    movzx rdx, bx ; W rdx zapisujemy długość danych w fragmencie.
    add edx, [rel buffer_pos] ; Dodajemy długość danych w fragmencie do pozycji w buforze.
    xor rcx, rcx ; Zerujemy licznik.
    cmp edx, [rel buffer_end] ; Sprawdzamy, czy dane mieszczą się w buforze.
    jb copy_data ; Jeśli tak, to wczytujemy dane.
    ; Jeśli nie, dane nie zmieściły się w buforze i trzeba odczytać ponownie plik.

read_loop: ; kopujemy pierwszy fragment do bufora danych
    mov al, [r9 + r13] ; Wczytujemy dane.
    mov [r8 + r10], al ; Zapisujemy dane.
    inc r10 ; Zwiększamy licznik.
    inc r13 ; Zwiększamy pozycję w buforze.
    cmp r13d, [rel buffer_end] ; Sprawdzamy, czy skończył się bufor.
    jb read_loop ; Jeśli nie, to wczytujemy kolejne dane.
    call read_file ; Wczytujemy kolejny fragment.


    movzx rbx, bx ; W rbx zapisujemy długość danych w fragmencie.
    sub rbx, r10 ; Odejmujemy wczytane dane od długości danych w fragmencie.
    add r8, r10 ; Przesuwamy wskaźnik na dane.
    xor r13, r13 ; Zerujemy pozycję w buforze.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję w buforze.
    xor rcx, rcx ; Zerujemy licznik.
    ; w tej chwili r8 mamy wskaznik na wolne miejsce w danych, 
    ; gdzie będziemy zapisywali dalszą część danych.


copy_data: ; kopiujemy dane z fragmentu do bufora danych
    test rbx, rbx ; Sprawdzamy, czy dane są puste.
    jz read_jump ; Jeśli tak, to wczytujemy przesunięcie.
copy_data_loop:
    mov al, [r9 + r13] ; Wczytujemy dane.
    mov [r8 + rcx], al ; Zapisujemy dane.
    inc rcx ; Zwiększamy licznik.
    inc r13 ; Zwiększamy pozycję w buforze.
    cmp rcx, rbx ; Sprawdzamy, czy wczytaliśmy dane w fragmencie.
    jb copy_data_loop ; Jeśli nie, to wczytujemy kolejne dane.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję w buforze.  


calculate_crc:
    ; Obliczanie sumy kontrolnej wygląda następująco:
    ; 1. Rejestr r15 jest rejestrem do którego będziemy wrzucali
    ;  od prawej strony bit po bicie dane robiąc shift left.
    ; W r12 będziemy trzymali wielomian crc (bez najbardziej znaczącego bitu) 
    ; przesunięty o odpowiednią ilość bitów w lewo, 
    ; tak żeby był przyklejony do lewej strony r12.
    ; W r10b trzymamy długość wielomianu crc w r12.
    ; 2. Jeśli w r15 nastąpi przeniesienie (czyli najbardziej znaczący
    ; bit był równy 1), to wykonujemy operację xor z r12 (wielomianem crc).
    ; 3. Powtarzamy operację dla wszystkich bitów w danych.
    ; 4. Na końcu programu, jak dane się skończą, to robimy 
    ; shift left 64 - poly_len razy, a po każdym shifcie sprawdzamy,
    ; czy było przeniesienie i jeśli tak, to xorujemy.
    ; 5. Na końcu w r15 mamy sumę kontrolną.

    mov r10b, [rel poly_len] 
    mov r12, [rel polynomial] 
    mov cl, 64 ; Maksymalna długość wielomianu crc.
    sub cl, r10b ; Odejmujemy długość wielomianu crc od 64.
    shl r12, cl ; Przyklejamy wielomian crc do lewej strony r12.
    mov rcx, [rel data_len] ; Długość danych.
    test rcx, rcx ; Sprawdzamy, czy dane są puste.
    jz read_jump ; Jeśli tak, to wczytujemy przesunięcie.

    lea r8, [rel data] ; W r8 zapisujemy wskaźnik na dane.
    xor r11, r11 ; R11 wskazuje na pierwszy bajt danych.
    mov bl, 8 ; W bl zapisujemy 8, bo tyle bitów w bajcie.
    mov al, [r8 + r11] ; Wczytujemy pierwszy bajt danych.

calculate_crc_loop: ; Pętla obliczająca sumę kontrolną.
    test bl, bl ; Sprawdzamy, czy skończyły się bity w bajcie.
    jz next_byte ; Jeśli tak, to wczytujemy kolejny bajt.
    shl al, 1 ; Przesuwamy bity w lewo.
    rcl r15, 1 ; Wrzucamy bit do r15 i robimy shift left.
    jnc post_xor ; Jeśli nie było przeniesienia, to nie robimy xor.
    xor r15, r12 ; Robimy xor z wielomianem crc.

post_xor: ; Po xorze (lub braku przeniesienia).
    dec bl ; Zmniejszamy licznik bitów w bajcie.
    jmp calculate_crc_loop

next_byte:
    inc r11 ; Zwiększamy wskaźnik na dane.
    cmp r11, rcx ; Sprawdzamy, czy skończyły się dane.
    je read_jump ; Jeśli tak, to wczytujemy przesunięcie.
    mov bl, 8 ; W bl zapisujemy 8, bo tyle bitów w bajcie.
    mov al, [r8 + r11] ; Wczytujemy kolejny bajt danych.
    jmp calculate_crc_loop

read_jump: ; Czytamy przesunięcie w danym fragmencie.
    lea r8, [rel jump_buffer] ; W r8 zapisujemy wskaźnik na bufor na przesunięcie.
    xor r14, r14
    mov eax, [rel buffer_end] ; W rax zapisujemy długość bufora.
    sub rax, r13 ; W rax zapisujemy ile bajtów 
    ; jeszcze nie przeczytaliśmy z bufora.
    cmp rax, 4 ; Sprawdzamy, czy przesunięcie mieści się w buforze.
    jae save_jump2 ; Jeśli tak, to wczytujemy przesunięcie.
    ; Jeśli nie, to trzeba zapisać bajty, które 
    ; się mieszczą i odczytać na nowo plik.

save_jump: ; Zapisujemy kolejne bajty przesunięcia w jump_buffer.
    mov [buffer_pos], r14d ; Wyzerowujemy pozycję w buforze.
    ; (jest to potrzebne do read_jump2)

    cmp rax, 0 ; Sprawdzamy, czy bufor się skończył.
    je read_jump2 ; Jeśli tak, to wczytujemy kolejny fragment.
    mov bl, [r9 + r13] ; Wczytujemy bajt przesunięcia.
    mov [r8 + r14], bl ; Zapisujemy bajt przesunięcia.
    inc r14 ; Zwiększamy indeks bajtu przesunięcia.
    inc r13 ; Zwiększamy pozycję w buforze.
    dec rax ; Zmniejszamy licznik.
    jmp save_jump 

read_jump2: 
    call read_file ; Wczytujemy kolejny fragment.

save_jump2: ; Chcemy zapisać przesunięcie w jump_buffer.
    mov r13d, [rel buffer_pos] ; W r13d zapisujemy pozycję w buforze.

; Zapisujemy przesunięcie w jump_buffer, a następnie w r14.
save_jump_loop: 
    mov bl, [r9 + r13] ; Wczytujemy bajt przesunięcia z bufora.
    mov [r8 + r14], bl ; Zapisujemy bajt przesunięcia do jump_buffer.
    inc r14 ; Zwiększamy indeks bajtu przesunięcia.
    inc r13 ; Zwiększamy pozycję w buforze.
    cmp r14, 4 ; Sprawdzamy, czy wczytaliśmy 4 bajty przesunięcia.
    jb save_jump_loop ; Jeśli nie, to wczytujemy kolejne bajty przesunięcia.
    mov r14d, dword [rel jump_buffer] ; W r14 zapisujemy przesunięcie.
    movsxd r14, r14d ; W r14 zapisujemy przesunięcie w 64 bitach.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję w buforze.

jump_next: ; Robimy przesunięcie do następnego fragmentu.
    
    mov rdx, [rel data_len] ; W rdx zapisujemy długość danych.
    neg rdx
    sub rdx, 6 ; Odejmujemy 6 bajtów (2 bajty długości danych i 4 bajty przesunięcia).
    cmp r14, rdx ; Sprawdzamy, czy przesunięcie jest na samego siebie.
    je end ; Jeśli tak, to to jest ostatni fragment.

    add r13d, r14d ; Dodajemy przesunięcie do pozycji w buforze.
    jo jump_out_of_buffer ; Jeśli nastąpił overflow, to trzeba odczytać ponownie plik.
    cmp r13d, [rel buffer_end] ; Sprawdzamy, czy przesunięcie mieści 
    ; się w górnej grancy bufora.
    jae jump_out_of_buffer ; Jeśli nie, to trzeba odczytać ponownie plik.
    cmp r13, 0 ; Sprawdzamy, czy przesunięcie mieści 
    ; się w dolnej grancy bufora.
    jl jump_out_of_buffer ; Jeśli nie, to trzeba odczytać ponownie plik.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję w buforze.
    jmp read_data_length ; Jeśli nie, to wczytujemy długość danych kolejnego fragmentu.

jump_out_of_buffer: ; Przesunięcie wychodzi poza bufor.
    mov r13d, [rel buffer_pos] ; W r13 zapisujemy pozycję w buforze.
    xor rax, rax
    mov eax, [rel buffer_end] ; W rax zapisujemy długość danych w buforze.
    sub rax, r13 ; Odejmujemy pozycję w buforze od długości danych w buforze.
    sub r14, rax ; Odejmujemy długość danych w buforze od przesunięcia.
    mov rax, SYS_LSEEK
    mov rdi, [rel file_descriptor]
    mov rsi, r14 ; Przesunięcie.
    mov rdx, 1 ; Skąd przesuwamy.
    syscall
    test rax, rax ; Sprawdzamy, czy przesunięcie się powiodło.
    js error ; Jeśli nie, to błąd.
    call read_file ; Wczytujemy kolejny fragment.
    xor r13, r13 ; Zerojemy pozycję w buforze.
    mov [rel buffer_pos], r13d ; Zapisujemy pozycję 0 w buforze.
    jmp read_data_length ; Wczytujemy długość danych kolejnego fragmentu.


end: ; zakończenie programu
    ; Trzeba dokończyć liczenie sumy kontrolnej z r15.
    mov r10b, [rel poly_len] ; Długość wielomianu crc.
    mov r12, [rel polynomial] ; Wielomian crc.
    mov cl, 64 ; Maksymalna długość wielomianu crc.
    sub cl, r10b ; Odejmujemy długość wielomianu crc od 64.
    shl r12, cl ; Przyklejamy wielomian crc do lewej strony r12.
    mov cl, 64 ; Licznik, ile razy musimy zrobić shift left.
control_sum_loop: ; Pętla obliczająca sumę kontrolną.
    test cl, cl
    jz save_crc
    shl r15, 1 ; Przesuwamy bity w lewo.
    jnc control_sum_post_xor ; Jeśli nie było przeniesienia, to nie robimy xor.
    xor r15, r12 ; Robimy xor z wielomianem crc.

control_sum_post_xor: ; Po xorze (lub braku przeniesienia).
    dec cl ; Zmniejszamy licznik.
    jmp control_sum_loop

save_crc: ; Zapisujemy sumę kontrolną.
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
    mov byte [rax + rcx], 10 ; Znak nowej linii.
    inc rcx ; Liczba bajtów w sumie kontrolnej.
    mov rax, SYS_WRITE 
    mov rdi, STD_OUT 
    lea rsi, [rel control_sum] ; Suma kontrolna.
    mov rdx, rcx ; Długość sumy kontrolnej.
    syscall
    test rax, rax ; Sprawdzamy, czy zapis się powiódł.
    js error ; Jeśli nie, to błąd.
    ; Jeśli tak, to zamykamy plik i kończymy program.
    jz error ; Jeśli zapisano 0 bajtów, to błąd.

    mov rax, SYS_CLOSE 
    mov rdi, [rel file_descriptor]
    syscall
    test rax, rax ; Sprawdzamy, czy zamknięcie pliku się powiodło.
    js exit

    mov rax, SYS_EXIT 
    xor rdi, rdi ; Kod wyjścia 0.
    syscall


error: ; Zamykamy plik, bo wystąpił błąd.
    mov rax, SYS_CLOSE 
    mov rdi, [file_descriptor] 
    syscall
    
exit: ; Wyjście z programu.
    mov rax, SYS_EXIT 
    mov rdi, 1 ; Kod błędu.
    syscall
