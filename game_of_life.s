bits 64

SECTION .rodata
; syscall information
SYSCALL_WRITE:          equ 1
SYSCALL_NANOSLEEP:      equ 35
SYSCALL_EXIT:           equ 60
STDOUT:                 equ 1
EXIT_SUCCESS:           equ 0
; UTF8 chars
LIVE_CELL:              db 0x96, 0x88
DEAD_CELL:              db 0xa0, 0x80
; ANSI escapes
ENTER_ALT_SCREEN:       db 1bh,"[?1049h"    ; These three escapes work on xterm-256
ENTER_ALT_SCR_LEN:      equ $-ENTER_ALT_SCREEN
EXIT_ALT_SCREEN:        db 1bh,"[?1049l"    ; I should be using terminfo
EXIT_ALT_SCR_LEN:       equ $-EXIT_ALT_SCREEN
UP_TO_BEGINNING:        db 1bh,"[20A"
UP_TO_BEGINNING_LEN:    equ $-UP_TO_BEGINNING
; Grid dimensions
GRID_SIDE_LEN:          equ 20
TOTAL_GRID_LEN:         equ GRID_SIDE_LEN * GRID_SIDE_LEN ; Grid length
; Sleep between generation
SLEEP_TIME:
    tv_sec  dq 0
    tv_nsec dq 500000000    ; 0.5 seconds

SECTION .text
global _start
_start:
    mov rdx, [rsp + 24] ; argv[2] - generations

.atoi_loop:
    ; Ascii to int, inlined
    ; Result in rbx
    cmp byte[rdx], 48
    jl .exit_atoi
    imul rbx, 10
    movzx rax, byte[rdx]
    add rbx, rax
    sub rbx, 48
    inc rdx
    jmp .atoi_loop
.exit_atoi:
    mov rdx, [rsp + 16] ; argv[1] - the grid

.initialize:
    ; "Initialize" the grid, convert "X" to 1, "." to 0
    cmp byte[rdx], 46   ; Compare mem with '.' char
    jl .exit_init       ; if less it means we hit the null byte
    setne byte[rdx]
    inc rdx
    jmp .initialize
.exit_init:
    mov r8, [rsp + 16]  ; r8 is the initialized grid
                        ; rbx is the number of generations to simulate
    call enter_screen
.sim_loop_head:
    call print_grid_utf8    ; Print the grid once per generation
    call sleep_half_second  ; Wait half a second before doing the next generation
    cmp bx, 0           ; Generation loop counter, when 0 exit
    je .sim_loop_end
    xor ecx, ecx        ; Loop counter
.inner_loop_head:
    cmp cx, 400         ; Stop at 400 - TODO: unroll loop
    je .inner_loop_end
    ; Loop Body

.neighbor_sum:
    mov rdx, GRID_SIDE_LEN
    mov ax, cx          ; Divide loop counter / index by GRID_SIDE_LEN
    div dl              ; Remainder in AH (X pos), quotient in AL (Y pos)
    xor r11,r11         ; Hold neighbor sum in r11
.neighbor_sum_unrolled_loop:
    movzx r13, al         ; We will use r13 for the modified Y pos
    movzx r12, ax         ; We will use r12 for the modified X pos
    shr r12, 8

    dec r12
    dec r13
    call get_index          ; -1, -1 top left neighbor
    add r11, r15

    inc r13
    call get_index          ; -1, 0  left neighbor
    add r11, r15

    inc r13
    call get_index          ; -1, 1 bottom left neighbor
    add r11, r15

    inc r12
    call get_index          ; 0, 1 bottom neighbor
    add r11, r15

    inc r12
    call get_index          ; 1, 1 bottom right neighbor
    add r11, r15

    dec r13
    call get_index          ; 1, 0 right neighbor
    add r11, r15

    dec r13
    call get_index          ; 1, -1 top right neighbor
    add r11, r15

    dec r12
    call get_index          ; 0, -1 top neighbor
    add r11, r15
.neighbor_sum_unrolled_loop_done:
    xor rax, rax
    cmp r11, 2
    sete al
    mul byte [r8 + rcx]             ; If a cell has two neighbors and is alive, it continues to be alive
    mov r13, rax
    cmp r11, 3
    sete al
    add r13, rax                     ; If a cell has three neighbors its alive
    mov byte [new_grid + rcx], r13b ; Store the results
    inc cx
    jmp .inner_loop_head
.inner_loop_end:
    dec bx
    
    ; Copy new_grid to stack in place of the current grid
    mov rcx, 400
.memcpy_loop:
    movzx rax, byte [new_grid + rcx]
    mov byte [r8 + rcx], al
    dec rcx
    jl .sim_loop_head
    jmp .memcpy_loop
.sim_loop_end:
    call exit_screen

.exit_prog:
    mov rax, SYSCALL_EXIT
    mov rdi, EXIT_SUCCESS
    syscall

mod:
    ; Arg passed in r14
    ; Result returned in r14
    ; Clobbers r14
    ; Implements true modulo operation - not the same as the remainder
    ; int mod(n)
    ; {
    ;   return (n % GRID_SIDE_LEN + GRID_SIDE_LEN ) % GRID_SIDE_LEN;
    ; }
    push rax
    push rbx

    mov rax,r14
    mov rbx, GRID_SIDE_LEN
    idiv bl          ; Remainder in AH
    and rax, 0xffff ; Clear upper 48 bits of signed int
    shr rax, 8
    movsx r14, al   ; n % GRID_SIDE_LEN
    add r14, rbx    ; n % GRID_SIDE_LEN + GRID_SIDE_LEN

    mov rax,r14
    idiv bl          ; Remainder in AH
    and rax, 0xffff ; Clear upper 48 bits of signed int
    shr rax, 8
    movsx r14, al   ; (n % GRID_SIDE_LEN + GRID_SIDE_LEN) % GRID_SIDE_LEN

    pop rbx
    pop rax
    ret

get_index:
    ; Arg passed in r12 and r13
    ; Result returned in r15
    ; Clobbers r14, r15
    ; Grid is known to be in r8
    ; Returns the 1D index of a 2D point
    ; int get_index(x, y)
    ; {
    ;   return grid[mod(x)+mod(y) * GRID_SIDE_LEN];
    ; }
    mov r14, r13            ; Move Y pos into r14 and mod it
    call mod
    mov r15, r14
    imul r15, GRID_SIDE_LEN            ; mod(y) * GRID_SIDE_LEN
    mov r14, r12            ; Move X pos into r14 and mod it
    call mod
    add r15, r14            ; mod(y) * GRID_SIDE_LEN + mod(x)
    movzx r15, byte[r8 + r15] ; grid[mod(y) * GRID_SIDE_LEN + mod(x)]
    ret

enter_screen:
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [ENTER_ALT_SCREEN]     ; Point to string
    mov rdx, ENTER_ALT_SCR_LEN      ; Str len
    syscall
    ret

exit_screen:
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [EXIT_ALT_SCREEN]     ; Point to string
    mov rdx, EXIT_ALT_SCR_LEN      ; Str len
    syscall
    ret

print_grid_utf8:
    ; Prints the grid using utf8 chars
    ; █ represents a live cell and is encoded as hex e2 96 88
    ; ⠀ represents a dead cell and is encoded as hex e2 a0 80
    ; At the end of each row we need a new line character: 0x20
    push rax
    push rbx
    push rcx
    push rdx

    xor rax, rax
    xor rbx, rbx
    mov rcx, 20             ; Next line break at index 20
    xor rdx, rdx

.loop:
    cmp rbx, TOTAL_GRID_LEN
    je .loop_end

    or byte [r8 + rbx], 0                ; Check current grid state
    cmovz dx, word [DEAD_CELL]             ; If zero, move dead cell char
    cmovnz dx, word [LIVE_CELL]            ; If one, move live cell char
    mov word [utf8_grid + rax], 0xe2
    inc rax
    mov word [utf8_grid + rax], dx

    add rax, 2                      ; Advance grid str point by 2
    inc rbx
    cmp rbx, rcx                    ; Check if a new line needs to be printed
    jne .loop

.ins_line_brk:
    mov byte [utf8_grid + rax], 0ah ; Add new line char
    inc rax                         ; incr string pointer
    add rcx, GRID_SIDE_LEN          ; Next line break is 20 chars later
    jmp .loop

.loop_end:
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [utf8_grid]    ; Point to string
    mov rdx, TOTAL_GRID_LEN ; Str len
    add rdx, TOTAL_GRID_LEN 
    add rdx, TOTAL_GRID_LEN ; Each char is three bytes
    add rdx, GRID_SIDE_LEN  ; Number of new lines
    syscall

    call return_cursor_to_top

    pop rdx
    pop rcx
    pop rbx
    pop rax
    ret

return_cursor_to_top:
    ; Uses ANSI escape sequences to return the cursor to the first line
    ; This gets called on every print iteration
    ; Clobbers rax, rdi, rsi, rdx
    mov rax, SYSCALL_WRITE
    mov rdi, STDOUT
    lea rsi, [UP_TO_BEGINNING]
    mov rdx, UP_TO_BEGINNING_LEN
    syscall
    ret

sleep_half_second:
    ; Sleeps for half a second
    ; Clobbers rax, rdi, rsi
    mov rax, SYSCALL_NANOSLEEP
    mov rdi, SLEEP_TIME
    xor rsi, rsi
    syscall
    ret

SECTION .bss
new_grid: resb 400
utf8_grid: resb 1220