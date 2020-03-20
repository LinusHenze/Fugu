//
//  shellcode.S
//  iStrap
//
//  Created by Linus Henze on 26.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#define O_WRONLY    0x0001
#define O_CREAT     0x0200
#define FWASWRITTEN 0x10000
#define IO_NOAUTH   0x8000

.align 4
.text

.globl rw_root_shellcode_start
rw_root_shellcode_start:
    sub sp, sp, 0x10    // Make some space on the stack
    str lr, [sp,#0x8]   // Store lr

    bl vfs_rootmountalloc_internal // Do the call
    // Now patch the mount options
    ldr w1, [x0,#0x70]  // Load mount options
    bic w1, w1, #1      // Clear MNT_RDONLY
    str w1, [x0,#0x70]  // Write changes

    ldr lr, [sp,#8]     // Restore lr
    add sp, sp, 0x10    // Restore stack
    ret

vfs_rootmountalloc_internal:
    adr x16, vfs_rootmountalloc_internal_loc // Load offset pointer
    ldr x16, [x16]                           // Get offset
    adr x17, rw_root_shellcode_start         // Get start of shellcode
    sub x16, x17, x16                        // Calculate real address of kernel_mount
    br  x16                                  // Jump to vfs_rootmountalloc_internal

.globl rw_root_shellcode_got
rw_root_shellcode_got:
vfs_rootmountalloc_internal_loc:
    .quad 0 // vfs_rootmountalloc_internal

.globl rw_root_shellcode_end
rw_root_shellcode_end:

.globl devfs_shellcode_start
devfs_shellcode_start:
    // Save lr to stack and save the last parameter on the
    // correct stack location
    sub sp, sp, 0x20    // Make some space on the stack
    str lr, [sp,#0x18]  // Store lr
    ldr x16, [sp,#0x20] // Load context
    str x16, [sp]       // Store context

    bl  kernel_mount    // Do the devfs mount

    // Create iDownload
    adr x0, iDownload_file_name
    adr x1, devfs_file_buffer
    ldr x1, [x1]
    adr x2, devfs_file_size
    ldr x2, [x2]
    ldr x3, [sp,#0x20]
    mov x4, 493
    bl create_write_file

end:
    ldr lr, [sp,#0x18]  // Restore lr
    add sp, sp, 0x20    // Restore stack
    ret

/*
 * Parameters:
 * x0: Name
 * x1: Buffer
 * x2: Size
 * x3: Context
 * x4: Permissions
 */
create_write_file:
    // Save lr to stack and save the last parameter on the
    // correct stack location
    sub sp, sp, 0x40    // Make some space on the stack
    str lr, [sp,#0x38]  // Store lr
    str x0, [sp,#0x30]  // Store name
    str x1, [sp,#0x28]  // Store buffer
    str x2, [sp,#0x20]  // Store size
    str x3, [sp,#0x18]  // Store context

    // Now create file
    // Name already in x0
    mov x1, O_CREAT | O_WRONLY // File mode
    mov x2, x4          // Permissions
    mov x3, 0           // flags
    mov x4, sp          // vpp -> out
    ldr x5, [sp,#0x18]  // Context
    bl vnode_open
    cmp x0, 0
    b.eq vnode_open_noerr
    mov x1, 0x1234
    ldr x1, [x1]        // Crash

vnode_open_noerr:
    // Now write data to file
    // Get proc
    ldr x0, [sp,#0x18]        // Load context
    bl vfs_context_proc

    // Save proc
    str x0, [sp,#0x8]         // Save

    // Get cred
    ldr x0, [sp,#0x18]        // Load context
    bl vfs_context_ucred

    // Now do the write!
    mov x7, x0                // Set creds
    mov x0, #1                // Mode = UIO_WRITE
    ldr x1, [sp]              // File context = The one we created
    ldr x2, [sp,#0x28]        // File buffer
    ldr x3, [sp,#0x20]        // File size
    mov x4, 0                 // Offset, 0
    mov x5, 1                 // UIO_SYSSPACE
    mov x6, IO_NOAUTH         // Flags, do not authenticate
    // Credentials already set
    ldr x16, [sp,#0x8]        // Get proc
    sub sp, sp, 0x10          // Adjust stack
    str xzr, [sp]             // Aresid = NULL
    str x16, [sp,#0x8]        // Set proc
    // Call!
    bl  vn_rdwr
    add sp, sp, 0x10          // Adjust stack
    cmp x0, 0
    b.eq vnode_write_noerr
    mov x1, 0x5678
    ldr x1, [x1]              // Crash

vnode_write_noerr:
    ldr x0, [sp]              // File context
    mov x1, FWASWRITTEN
    ldr x2, [sp,#0x18]        // Context
    bl vnode_close

    // Restore stack
    ldr lr, [sp,#0x38]        // Restore lr
    add sp, sp, 0x40          // Restore stack
    ret

/*
 * Pass the ctx parameter on the stack!
 * Must be at sp, and sp must be 16 byte aligned
 *
 * x16 and x17 will be trashed
 */
kernel_mount:
    adr x16, devfs_real_kernel_mount // Load offset pointer
    b   devfs_general_symcall

vnode_open:
    adr x16, devfs_vnode_open        // Load offset pointer
    b   devfs_general_symcall

vnode_close:
    adr x16, devfs_vnode_close       // Load offset pointer
    b   devfs_general_symcall

vfs_context_proc:
    adr x16, devfs_vfs_context_proc  // Load offset pointer
    b   devfs_general_symcall

vfs_context_ucred:
    adr x16, devfs_vfs_context_ucred // Load offset pointer
    b   devfs_general_symcall

vn_rdwr:
    adr x16, devfs_vn_rdwr           // Load offset pointer
    b   devfs_general_symcall

// Relative offset must be in x16!
devfs_general_symcall:
    ldr x16, [x16]                   // Get offset
    adr x17, devfs_shellcode_start   // Get start of shellcode
    sub x16, x17, x16                // Calculate real address of function
    br  x16                          // Jump to function

.globl devfs_shellcode_got
devfs_shellcode_got:
devfs_real_kernel_mount:
    .quad 0 // kernel_mount

devfs_vnode_open:
    .quad 0 // vnode_open

devfs_vnode_close:
    .quad 0 // vnode_close

devfs_vfs_context_proc:
    .quad 0 // vfs_context_proc

devfs_vfs_context_ucred:
    .quad 0 // vfs_context_ucred

devfs_vn_rdwr:
    .quad 0 // vn_rdwr

devfs_file_buffer:
    .quad 0 // file_buffer

devfs_file_size:
    .quad 0 // file_size

iDownload_file_name:
    .asciz "/iDownload"

.globl devfs_shellcode_end
devfs_shellcode_end:
    nop
