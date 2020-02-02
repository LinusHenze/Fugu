//
//  start.S
//  iStrap Loader
//
//  Created by Linus Henze on 19.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

.section .text.boot

.align 2

.global start
start:
    // Small magic sequence, should appear at start of the loader file
    nop
    nop
    nop
    nop

    // First, detect if we need to run ttbr0_hooker
    // Check if MMU is enabled, run hooker if not
    mrs x2, SCTLR_EL1
    and x2, x2, #0x1
    cmp x2, #0x1
    b.ne run_hooker

    // MMU is enabled
    // This is the start function of the iStrap loader
    // x0 -> Address of iBoot/Kernel
    // x1 -> Argument
    // Save them into x0 -> x29, x1 -> x28
    // This is were the boot trampoline expects them to be
    // And we might overwrite the mov sequence setting them
    mov x29, x0
    mov x28, x1

    // We should also save lr somewhere. Let's use x25
    mov x25, lr

    // Okay, we're ready
    // Jump to loader main
    mov x0, x29
    mov x1, x28
    bl main_loader

exit:
    // Before exiting, restore lr from x25
    mov lr, x25

    // Now we should disable interrupts
    // We definiteley overwrote the interrupt disabling code
    msr DAIFSet, #0xf
    isb // <- Not all SecureROM's do that, but it doesn't hurt

    // Also restore x0, x1 in case we didn't overwrite that part
    mov x0, x29
    mov x1, x28

    // Now we can return
    ret

run_hooker:
    // MMU is disabled
    // Save lr somewhere (data section...)
    adr x1, hooker_lr_save
    str lr, [x1]

    // Call ttbr0_hooker
    bl ttbr0_hooker

    // Restore lr
    adr x1, hooker_lr_save
    ldr lr, [x1]

    // Return
    ret

.global asm_get_el
asm_get_el:
    mrs x0, CurrentEL
    lsr x0, x0, #2
    and x0, x0, #3
    ret

.globl asm_disable_mmu
asm_disable_mmu:
    mrs x0, SCTLR_EL1
    bic x0, x0, #1
    msr SCTLR_EL1, x0
    dsb sy
    isb
    ret

.globl asm_enable_mmu
asm_enable_mmu:
    mrs x0, SCTLR_EL1
    orr x0, x0, #1
    msr SCTLR_EL1, x0
    dsb sy
    isb
    ret

.globl asm_read_ttbr0
asm_read_ttbr0:
    mrs x0, TTBR0_EL1
    ret

.globl asm_write_ttbr0
asm_write_ttbr0:
    msr TTBR0_EL1, x0
    isb sy
    ret

.globl asm_ttbr0_hook_shellcode
asm_ttbr0_hook_shellcode:
    mov x2, #0x180000000
    br x2

.globl ttbr0_write_sequence_el1
ttbr0_write_sequence_el1:
    msr    TTBR0_EL1, x0
    isb    sy
    ret

.globl sctlr_write_sequence_el1
sctlr_write_sequence_el1:
    msr    SCTLR_EL1, x0
    dsb    sy
    isb    sy

.globl custom_sctlr_write_sequence_el1
custom_sctlr_write_sequence_el1:
    bic x0, x0, 0x80000 // Who needs w^x anyway? ;)
    msr SCTLR_EL1, x0
    dsb sy
    isb sy
    ret

.global iBoot_hook_sequence
iBoot_hook_sequence:
    msr DAIFSet, #0xF
    mov x29, x0
    mov x28, x1

.global iBoot_hook
iBoot_hook:
    mov x2, #0x180000000
    blr x2

.data
hooker_lr_save:
    .quad 0

hooker_override:
    .quad 0
