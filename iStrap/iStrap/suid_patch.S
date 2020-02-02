//
//  suid_patch.S
//  iStrap
//
//  Created by Linus Henze on 28.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

.align 4
.text

.globl setuid_patch_start
setuid_patch_start:
    sub sp, sp, 0x50
    str lr,     [sp,#0x40]
    stp x6, x7, [sp,#0x30]
    stp x4, x5, [sp,#0x20]
    stp x2, x3, [sp,#0x10]
    stp x0, x1, [sp]

    cmp x3, 0
    b.eq setuid_out

    // Get file attributes
    sub sp, sp, 0x400

    str xzr, [sp]
    mov x0, 0x380       // va_active: UID, GID, MODE
    str x0, [sp,#0x8]
    str xzr, [sp,#0x10]
    mov x0, x3
    mov x1, sp
    // x2 already set
    bl vnode_getattr

    // Check if succeded
    cmp x0, 0
    b.eq setuid_getattr_ok
    // Crash if not
    mov x16, 0
    ldr x16, [x16]

setuid_getattr_ok:
    // Now check for setuid
    ldr w0, [sp,#0x4C]      // Load mode
    ldr w2, [sp,#0x44]      // Load uid
    add sp, sp, 0x400       // Reset stack, not needed anymore
    and w0, w0, 0x800       // Test for setuid bit
    cmp w0, 0
    b.eq setuid_out         // Not set if 0
    // Patch the credentials
    ldp x0, x1, [sp]        // Load old and new
    // Patch!
    str w2, [x0,#0x18]      // Patch old (real user id)
    str w2, [x0,#0x20]      // Patch old (saved user id)
    str w2, [x1,#0x18]      // Patch new (real user id)
    str w2, [x1,#0x20]      // Patch new (saved user id)

setuid_out:
    ldr lr,     [sp,#0x40]
    ldp x6, x7, [sp,#0x30]
    ldp x4, x5, [sp,#0x20]
    ldp x2, x3, [sp,#0x10]
    ldp x0, x1, [sp]
    add sp, sp, 0x50
    b amfi_exec_check

amfi_exec_check:
    adr x16, amfi_exec_check_addr        // Load offset pointer
    b   setuid_general_symcall

vnode_getattr:
    adr x16, vnode_getattr_loc       // Load offset pointer
    b   setuid_general_symcall

// Relative offset must be in x16!
setuid_general_symcall:
    ldr x16, [x16]                   // Get offset
    adr x17, setuid_patch_start      // Get start of shellcode
    sub x16, x17, x16                // Calculate real address of function
    br  x16                          // Jump to function

.globl setuid_patch_got
setuid_patch_got:
amfi_exec_check_addr:
    .quad 0
vnode_getattr_loc:
    .quad 0

.globl setuid_patch_end
setuid_patch_end:
