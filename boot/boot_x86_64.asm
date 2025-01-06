global start

extern main

; Multiboot2 header must be placed at 0x1000 (.1M) right before the 32bit code (see boot/linker.ld)
section .multiboot2_section
multiboot2_header:

MULTIBOOT2_MAGIC equ 0xe85250d6
MULTIBOOT2_CHECKSUM_BASE equ 0x100000000
MULTIBOOT2_ARCH_I386 equ 0
MULTIBOOT2_TAG_END_TYPE equ 0
MULTIBOOT2_TAG_END_FLAGS equ 0
MULTIBOOT2_TAG_END_SIZE equ 8

.start:
    dd MULTIBOOT2_MAGIC
    dd MULTIBOOT2_ARCH_I386
    dd .end - .start
    dd MULTIBOOT2_CHECKSUM_BASE - (MULTIBOOT2_MAGIC + MULTIBOOT2_ARCH_I386 + (.end - .start))
.end_tag:
    dw MULTIBOOT2_TAG_END_TYPE
    dw MULTIBOOT2_TAG_END_FLAGS
    dd MULTIBOOT2_TAG_END_SIZE
.end:

; =============================================================================
; 32bit Code
; =============================================================================
section .text
[BITS 32]
start:
protected_mode_code_start:
    ; Called by multiboot with arguments in registers
    mov [multiboot2_info_physical_address], ebx
    mov esp, entry_stack_top

    call check_multiboot
    call check_cpuid
    call check_long_mode

    call enable_sse
    call setup_page_tables
    call enable_paging

    ; enter 64bit long mode
    lgdt [gdt.register]
    jmp gdt.code_segment_descriptor:long_mode_start
.halt:
    cli
    hlt
    jmp .halt

check_multiboot:
    cmp eax, 0x36d76289
    jne error
    ret

check_cpuid:
    pushfd
    pop eax
    mov ecx, eax
    xor eax, 1 << 21
    push eax
    popfd
    pushfd
    pop eax
    push ecx
    popfd
    cmp eax, ecx
    je error
    ret

check_long_mode:
    mov eax, 0x80000000
    cpuid
    cmp eax, 0x80000001
    jb error
    mov eax, 0x80000001
    cpuid
    test edx, 1 << 29
    jz error
    ret

enable_sse:
    mov eax, cr0
    and ax, 0xFFFB
    or ax, 0x2
    mov cr0, eax
    mov eax, cr4
    or ax, 0b11 << 9
    mov cr4, eax
    ret

; PML4 4k pages identity mapping of the first Gb
PAGE_PRESENT       equ 1 << 0
PAGE_WRITABLE      equ 1 << 1

; 1 Gib identity mapping (can be reduced if boot is too slow)
; 1 L4 x 1 L3 x 512 L2 x 512 L1 x 4096 byte = 1073741824 byte = 1Gib
setup_page_tables:
    mov ebx, page_table_l3 + PAGE_WRITABLE + PAGE_PRESENT ; L3 + present, writable bits
    mov [page_table_l4], ebx

    mov ebx, page_table_l2 + PAGE_WRITABLE + PAGE_PRESENT ; L2 + present, writable bits
    mov [page_table_l3], ebx

    mov ebx, page_table_l1 + PAGE_WRITABLE + PAGE_PRESENT ; L1 + present, writable bits
    mov edi, page_table_l2 ; destination pointer
    mov ecx, 512 ; counter
.loop_l2:
    mov DWORD [edi], ebx
    add ebx, 512 * 8 ; each L2 entry points to the same indexed L1 table
    add edi, 8
    dec ecx
    jnz .loop_l2

    mov ebx, PAGE_WRITABLE + PAGE_PRESENT ; physical page 0 address + present, writable bits
    mov edi, page_table_l1 ; destination pointer
    mov ecx, 512 * 512 ; counter
.loop_l1:
    mov DWORD [edi], ebx
    add ebx, 4096 ; physical page offset
    add edi, 8
    dec ecx
    jnz .loop_l1
    ret

enable_paging:
    mov eax, page_table_l4
    mov cr3, eax

    ; enable physical address extension (PAE) bit
    mov eax, cr4
    or eax, 1 << 5
    mov cr4, eax

    ; enable long mode (LM) bit
    mov ecx, 0xC0000080 ; EFER MSR
    rdmsr
    or eax, 1 << 8 ; LM bit
    wrmsr

    ; enable paging
    mov eax, cr0
    or eax, 1 << 31
    mov cr0, eax

    ret

error:
.halt:
    cli
    hlt
    jmp .halt
protected_mode_code_end:

; =============================================================================
; Uninitialized memory
; =============================================================================
section .bss
align 4096
page_table_l4:
    resb 512 * 8
page_table_l3:
    resb 512 * 8
page_table_l2:
    resb 512 * 8
page_table_l1:
    resb 512 * 512 * 8

align 16 ; stack must be 16 byte aligned!
entry_stack_bottom:
    resb 1024 * 16
entry_stack_top:

multiboot2_info_physical_address:
    resb 4

; =============================================================================
; Initialized memory
; =============================================================================
section .rodata

; Access bits
PRESENT       equ 1 << 7
NOT_SYS       equ 1 << 4
EXEC          equ 1 << 3
DC            equ 1 << 2
RW            equ 1 << 1
ACCESSED      equ 1 << 0

; Flags bits
GRAN_4K       equ 1 << 7
LONG_MODE     equ 1 << 5

align 8
gdt:
    dq 0 ; required zero entry

; See AMD64: 4.8.1 Code-Segment Descriptors
.code_segment_descriptor: equ $ - gdt
    dw 0xFFFF                        ; Limit bits 0-15
    dw 0			     ; Base  bits 0-15
    db 0                             ; Base  bits 16-23
    db PRESENT | NOT_SYS | EXEC | RW ; Access
    db GRAN_4K | LONG_MODE | 0xF     ; Flags & Limit bits 16-19
    db 0                             ; Base  bits 24-31

; See AMD64: 4.8.2 Data-Segment Descriptors
.data_segment_descriptor: equ $ - gdt
    dw 0xFFFF                        ; Limit bits 0-15
    dw 0	                     ; Base  bits 0-15
    db 0                             ; Base  bits 16-23
    db PRESENT | NOT_SYS | RW        ; Access
    db 0xF			     ; Flags & Limit bits 16-19
    db 0                             ; Base  bits 24-31

; GDT register
.register:
    .length: dw $ - gdt - 1
    .address: dq gdt

; =============================================================================
; 64bit Code
; =============================================================================
section .text
[BITS 64]
long_mode_start:
    cli ; interrupts are setup ASAP in main code

    ; cs register is set to gdt.code_segment_descriptor by long jump
    mov ax, gdt.data_segment_descriptor
    mov ss, ax
    mov ds, ax
    mov es, ax
    mov fs, ax
    mov gs, ax

    mov rsp, entry_stack_top
    mov rbp, entry_stack_top ; not really required

    ; Pass multiboot2 address via rax
    mov rax, [multiboot2_info_physical_address]
    call main
.halt:
    cli
    hlt
    jmp .halt

