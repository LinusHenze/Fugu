//
//  patch.c
//  iStrap
//
//  Created by Linus Henze on 26.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "patch.h"
#include "definitions.h"
#include "framebuffer.h"
#include "deviceTree.h"
#include "patchfinder.h"

#include <mach-o/loader.h>
#include <mach-o/nlist.h>

extern void devfs_shellcode_start(void);
extern void devfs_shellcode_got(void);
extern void devfs_shellcode_end(void);

extern void rw_root_shellcode_start(void);
extern void rw_root_shellcode_got(void);
extern void rw_root_shellcode_end(void);

extern void setuid_patch_start(void);
extern void setuid_patch_got(void);
extern void setuid_patch_end(void);

#define OFFSET_64(a, b) ((uint64_t) a - (uint64_t) b)

// FIXME: These shouldn't be static
#define TEXT_EXEC_BASE   0xFFFFFFF0070F0000ULL
#define KERNEL_FULL_BASE (void*) 0x820000000ULL

void *findTCFunc(void *stringLoc, DTMemoryEntry *kText_kxt, DTMemoryEntry *kText_krnl) {
    void *kTextKEXTEnd = (void*) ((uintptr_t) kText_kxt->start + kText_kxt->size);
    
    void *amfi_tc_str_xref = find_xref_to((void*) kText_kxt->start, kTextKEXTEnd, (uint64_t) stringLoc);
    if (!amfi_tc_str_xref) {
        puts("!!! FAILED TO FIND AMFI TC LOCATION !!!");
        puts("!!!           HANGING NOW           !!!");
        while (1) {}
    }
    
    void *amfi_tc_func1 = (void*) get_previous_bl_target(amfi_tc_str_xref, (void*) kText_kxt->start);
    if (!amfi_tc_func1) {
        puts("!!! FAILED TO FIND AMFI TC FUNC1 !!!");
        puts("!!!          HANGING NOW         !!!");
        while (1) {}
    }
    
    void *amfi_tc_func2 = (void*) get_next_bl_target(amfi_tc_func1, kTextKEXTEnd);
    if (!amfi_tc_func2) {
        puts("!!! FAILED TO FIND AMFI TC FUNC2 !!!");
        puts("!!!          HANGING NOW         !!!");
        while (1) {}
    }
    
    void *amfi_tc_static_func = (void*) get_next_bl_target(amfi_tc_func2, kTextKEXTEnd);
    if (!amfi_tc_static_func) {
        puts("!!! FAILED TO FIND AMFI TC STATIC FUNC !!!");
        puts("!!!             HANGING NOW            !!!");
        while (1) {}
    }
    
    uint32_t *amfi_tc_static_got = (uint32_t*) get_next_bl_target(amfi_tc_static_func, kTextKEXTEnd);
    if (!amfi_tc_static_got) {
        puts("!!! FAILED TO FIND AMFI TC STATIC GOT !!!");
        puts("!!!            HANGING NOW            !!!");
        while (1) {}
    }
    
    uint32_t adrpInst = amfi_tc_static_got[0];
    uint32_t ldrInst  = amfi_tc_static_got[1];
    
    uint64_t *amfi_tc_static_got_entry = (uint64_t*) aarch64_emulate_adrp_ldr(adrpInst, ldrInst, (uint64_t) amfi_tc_static_got);
    if (!amfi_tc_static_got_entry) {
        puts("!!! FAILED TO FIND AMFI TC STATIC GOT ENTRY !!!");
        puts("!!!               HANGING NOW               !!!");
        while (1) {}
    }
    
    uint32_t *tc_static_loc = (uint32_t*) ((*amfi_tc_static_got_entry - TEXT_EXEC_BASE) + kText_krnl->start);
    
    void *tc_static0_loc = (void*) aarch64_emulate_branch(*tc_static_loc, (uint64_t) tc_static_loc);
    
    return tc_static0_loc;
}

void *findRootmountallocCall(void *start, void *end, void *strLoc) {
    uint32_t *vfs_mountroot = find_xref_to(start, end, (uint64_t) strLoc);
    if (!vfs_mountroot) {
        return NULL;
    }
    
    while (vfs_mountroot < (uint32_t*) end) {
        if (aarch64_emulate_bl(*vfs_mountroot, (uint64_t) vfs_mountroot)) {
            return vfs_mountroot;
        }
        
        vfs_mountroot++;
    }
    
    return NULL;
}

void *findDevfsFunc(void *start, void *end) {
    uint32_t *cur = (uint32_t*) start;
    while (cur < (uint32_t*) end) {
        if ((*cur & 0xFFFFFFE0) == 0x528CAC80) {
            // mov w?, #0x6564
            
            // Make sure registers are the same
            uint32_t movk = *(cur + 1);
            
            if ((movk & 0x1F) == (*cur & 0x1F)) {
                // They are, now check for movk
                if ((movk & 0xFFFFFFE0) == 0x72ACCEC0) {
                    // movk w?, #0x6676, lsl #16
                    // Check for mov x1, 0
                    void *next_mov_x1_0 = find_next_instruction_threshold(cur, end, 0xD2800001, 0x10);
                    if (next_mov_x1_0 == NULL) {
                        cur++;
                        continue;
                    }
                    
                    // Now find the bl
                    while (1) {
                        if (aarch64_emulate_bl(*cur, (uint64_t) cur)) {
                            // This is a bl
                            return cur;
                        }
                        
                        cur++;
                    }
                }
            }
        }
        
        cur++;
    }
    
    puts("!!! FAILED TO FIND DEVFS FUNCTION !!!");
    puts("!!!          HANGING NOW          !!!");
    while (1) {}
}

void *find_cs_invalid_page(void *start, void *end) {
    // Looks like this:
    // cbz        wA, label
    // orr        wB,wB,#0x200
    // str        wB,[x??, #??]
    // label:
    // adrp       xC,??
    // ldr        wD,[xC, #??]
    // cbz        wD, label2
    // orr        wE,wE,#0x100
    // str        wE,[x??, #??]
    // label2:
    
    uint32_t *ptr = (uint32_t*) start;
    while (ptr < (uint32_t*) end) {
        if ((*ptr & 0xFFFFFFE0) == 0x34000060) {
            // Found cbz
            int orr1_regA = ptr[1] & 0x1F;
            int orr1_regB = (ptr[1] >> 5) & 0x1F;
            if (orr1_regA == orr1_regB && (ptr[1] & 0xFFFFFC00) == 0x32170000) {
                // Found first orr
                int str1_reg = ptr[2] & 0x1F;
                if (str1_reg == orr1_regA && (ptr[2] & 0xFFC00000) == 0xB9000000) {
                    // Found first store
                    // Skip two instructions
                    if ((ptr[5] & 0xFFFFFFE0) == 0x34000060) {
                        // Found second cbz
                        int orr2_regA = ptr[6] & 0x1F;
                        int orr2_regB = (ptr[6] >> 5) & 0x1F;
                        if (orr2_regA == orr2_regB && (ptr[6] & 0xFFFFFC00) == 0x32180000) {
                            // Found second orr
                            int str2_reg = ptr[7] & 0x1F;
                            if (str2_reg == orr2_regA && (ptr[7] & 0xFFC00000) == 0xB9000000) {
                                // Found second store
                                // This is our function!
                                return (void*) ((uintptr_t) function_find_start((void*) ptr, start) - 4);
                            }
                        }
                    }
                }
            }
        }
        
        ptr++;
    }
    
    puts("!!! FAILED TO FIND cs_invalid_page !!!");
    puts("!!!           HANGING NOW          !!!");
    while (1) {}
}

struct load_command *findLoadCommandOfType(uint8_t *kernel, struct load_command *begin, uint32_t type) {
    struct mach_header_64 *header = (struct mach_header_64*) kernel;
    if (header->magic != MH_MAGIC_64) {
        return NULL; //That's not a mach-o image
    }
    
    struct load_command *startCmd = (struct load_command*) (kernel + sizeof(struct mach_header_64));
    
    struct load_command *ldCmd = begin;
    if (ldCmd == NULL) {
        ldCmd = startCmd;
    } else {
        ldCmd = (struct load_command*) ((uintptr_t) ldCmd + ldCmd->cmdsize);
    }
    
    uintptr_t endAddr = (uintptr_t) startCmd + header->sizeofcmds;
    
    while ((uintptr_t) ldCmd < endAddr) {
        if (ldCmd->cmd == type) {
            return ldCmd;
        }
        ldCmd = (struct load_command*) ((uintptr_t) ldCmd + ldCmd->cmdsize);
    }
    
    return NULL;
}

struct segment_command_64 *findSegmentLoadCommand(uint8_t *kernel, char *segment) {
    struct load_command *ldCmd = findLoadCommandOfType(kernel, NULL, LC_SEGMENT_64);
    
    while (ldCmd != NULL) {
        struct segment_command_64 *sLdCmd = (struct segment_command_64*) ldCmd;
        if (strcmp(sLdCmd->segname, segment) == 0) {
            return (struct segment_command_64*) ldCmd;
        } else {
            ldCmd = findLoadCommandOfType(kernel, ldCmd, LC_SEGMENT_64);
        }
    }
    
    return NULL;
}

void *resolveSymbol(char *name) {
    void *kernel_start = KERNEL_FULL_BASE;
    while (*(uint32_t*) kernel_start != MH_MAGIC_64) {
        kernel_start++;
    }
    
    struct segment_command_64 *linkeditLoadCmd = findSegmentLoadCommand(kernel_start, "__LINKEDIT");
    if (!linkeditLoadCmd) {
        puts("!!! FAILED TO FIND LINKEDIT LC !!!");
        puts("!!!         HANGING NOW        !!!");
        while (1) {}
    }
    
    struct symtab_command *symtab = (struct symtab_command*) findLoadCommandOfType(kernel_start, NULL, LC_SYMTAB);
    if (!symtab) {
        puts("!!! FAILED TO FIND SYMTAB LC !!!");
        puts("!!!        HANGING NOW       !!!");
        while (1) {}
    }
    
    void *linkedit = (void*) ((uintptr_t) kernel_start + (uintptr_t) linkeditLoadCmd->fileoff);
    void *symTable = (void*) (linkedit + (symtab->symoff - linkeditLoadCmd->fileoff));
    void *stringTable = (void*) (linkedit + (symtab->stroff - linkeditLoadCmd->fileoff));
    
    struct nlist_64 *symEnts = (struct nlist_64*) symTable;
    
    for (unsigned int i = 0; i < symtab->nsyms; i++) {
        char *symbolStr = (char*) ((uintptr_t) stringTable + symEnts[i].n_un.n_strx);
        if (strcmp(symbolStr, name) == 0) {
            return (void*) ((uintptr_t) symEnts[i].n_value);
        }
    }
    
    return NULL;
}

#define RESOLVE_TEXT_SYMBOL(name) ((void*) ((uintptr_t) resolveSymbol(name) - (uintptr_t) TEXT_EXEC_BASE + (uintptr_t) kText->start))

void applyKernelPatches(boot_args *args, bool iDownloadPresent, void *iDownloadLoc, size_t iDownloadSize) {
    DTMemoryEntry *kStrings = dt_lookup_memory_map(args, "Kernel-__TEXT");
    if (!kStrings) {
        puts("!!! FAILED TO FIND TEXT SECTION !!!");
        puts("!!!         HANGING NOW         !!!");
        while (1) {}
    }
    
    DTMemoryEntry *kStrings_kext = dt_lookup_memory_map(args, "Kernel-__PRELINK_TEXT");
    if (!kStrings_kext) {
        puts("!!! FAILED TO FIND TEXT SECTION !!!");
        puts("!!!         HANGING NOW         !!!");
        while (1) {}
    }
    
    DTMemoryEntry *kText_kext = dt_lookup_memory_map(args, "Kernel-__PLK_TEXT_EXEC");
    if (!kText_kext) {
        puts("!!! FAILED TO FIND TEXT EXEC SECTION !!!");
        puts("!!!            HANGING NOW           !!!");
        while (1) {}
    }
    
    void *kTextKEXTEnd = (void*) ((uintptr_t) kText_kext->start + kText_kext->size);
    
    DTMemoryEntry *kText = dt_lookup_memory_map(args, "Kernel-__TEXT_EXEC");
    if (!kText) {
        puts("!!! FAILED TO FIND TEXT EXEC SECTION !!!");
        puts("!!!            HANGING NOW           !!!");
        while (1) {}
    }
    
    void *kTextEnd = (void*) ((uintptr_t) kText->start + kText->size);
    
    puts("[*] Searching for string locations...");
    
    sequence patchSequences[5];
    patchSequences[0].sequence = "%s: only allowed process can check the trust cache\n";
    patchSequences[0].location = NULL;
    patchSequences[0].size = 51;
    
    // APFS snapshot hack
    // Required for install
    patchSequences[1].sequence = "com.apple.os.update-";
    patchSequences[1].location = NULL;
    patchSequences[1].size = 20;
    
    // AMFI unsigned 1
    patchSequences[2].sequence = "run-unsigned-code";
    patchSequences[2].location = NULL;
    patchSequences[2].size = 18;
    
    // AMFI unsigned 2
    patchSequences[3].sequence = "AMFI: hook..execve() killing pid %u: Attempt to execute completely";
    patchSequences[3].location = NULL;
    patchSequences[3].size = 66;
    
    // AMFI unsigned 3
    patchSequences[4].sequence = "%s: Hash type is not SHA256 (%u) but %u";
    patchSequences[4].location = NULL;
    patchSequences[4].size = 39;
    
    bool sqFound = findSequences((void*) kStrings_kext->start, kStrings_kext->size, &patchSequences[0], 5);
    if (!sqFound) {
        puts("!!! FAILED TO FIND STRING LOCATIONS !!!");
        puts("!!!           HANGING NOW           !!!");
        while (1) {}
    }
    
    puts("[+] Strings found!");
    
    // Kill snapshots
    cpyMem(patchSequences[1].location, "com.apple.os.update_", 21);
    
    // First the pmap_lookup_in_static_trust_cache_0 patch
    // Kills code signature checks
    void *tc_static0_loc = findTCFunc(patchSequences[0].location, kText_kext, kText);
    
    cpyMem(tc_static0_loc, "\x20\x00\x80\xd2\xc0\x03\x5f\xd6", 8); // mov w0, 1; ret
    
    // AMFI unsigned 1
    void *run_unsigned = find_xref_to((void*) kText_kext->start, kTextKEXTEnd, (uint64_t) patchSequences[2].location);
    if (!run_unsigned) {
        puts("!!! FAILED TO FIND AMFI GET ENTITLEMENT !!!");
        puts("!!!             HANGING NOW             !!!");
        while (1) {}
    }
    
    void *entitlement_chk = (void*) get_next_bl_target(run_unsigned, kTextKEXTEnd);
    if (!entitlement_chk) {
        puts("!!! FAILED TO FIND AMFI GET ENTITLEMENT !!!");
        puts("!!!             HANGING NOW             !!!");
        while (1) {}
    }
    
    // *x2 = 1; return 0
    cpyMem(entitlement_chk, "\x20\x00\x80\x52\x40\x00\x00\x39\x00\x00\x80\x52\xc0\x03\x5f\xd6", 16);
    
    // AMFI unsigned 2
    uint32_t *nosig = (uint32_t*) find_xref_to((void*) kText_kext->start, kTextKEXTEnd, (uint64_t) patchSequences[3].location);
    if (!nosig) {
        puts("!!! FAILED TO FIND AMFI EXECV HOOK !!!");
        puts("!!!           HANGING NOW          !!!");
        while (1) {}
    }
    
    void *execChkStart = function_find_start(nosig, (void*) kText_kext->start);
    if (!execChkStart) {
        puts("!!! FAILED TO FIND AMFI EXECV HOOK !!!");
        puts("!!!           HANGING NOW          !!!");
        while (1) {}
    }
    
    execChkStart = (void*) ((uintptr_t) execChkStart - 4ULL);
    
    uint32_t *xrefExecChk = (uint32_t*) find_xref_to((void*) kText_kext->start, kTextKEXTEnd, (uint64_t) execChkStart);
    if (!xrefExecChk) {
        puts("!!! FAILED TO FIND AMFI EXECV HOOK !!!");
        puts("!!!           HANGING NOW          !!!");
        while (1) {}
    }
    
    uintptr_t shellcodeLength = (uintptr_t) &setuid_patch_end - (uintptr_t) &setuid_patch_start;
    void *shellcodeLoc = (void*) ((uintptr_t) kTextEnd - shellcodeLength);
    shellcodeLoc = (void*) ((uintptr_t) shellcodeLoc & ~(3ULL));
    
    // Patch the suid shellcode
    uint64_t *shPLoc = (uint64_t*) &setuid_patch_got;
    shPLoc[0] = OFFSET_64(shellcodeLoc, execChkStart);
    shPLoc[1] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vnode_getattr"));
    
    cpyMem(shellcodeLoc, &setuid_patch_start, shellcodeLength);
    
    // Now add entries
    // First the adrp
    uint32_t diff = (uint32_t) OFFSET_64(shellcodeLoc, xrefExecChk);
    uint32_t diffAdrp = (diff >> 12);
    uint32_t adrp = 0x90000000;
    adrp |= (diffAdrp & 0x3) << 29;
    adrp |= (diffAdrp >> 2) << 5;
    adrp |= *xrefExecChk & 0x1F;
    // Now the add
    uint32_t add = 0x91000000;
    add |= ((uintptr_t) shellcodeLoc & 0xFFF) << 10;
    add |= xrefExecChk[1] & 0x3FF;
    
    void *emu = (void*) aarch64_emulate_adrp_add(adrp, add, (uint64_t) xrefExecChk);
    if (emu != shellcodeLoc) {
        puts("!!! ADRP ADD CALCULATION FAILED !!!");
        puts("!!!         HANGING NOW         !!!");
        while (1) {}
    }
    
    xrefExecChk[0] = adrp;
    xrefExecChk[1] = add;
    
    // AMFI unsigned 3
    void *xref_hash_type = find_xref_to((void*) kText_kext->start, kTextKEXTEnd, (uint64_t) patchSequences[4].location);
    if (!xref_hash_type) {
        puts("!!! FAILED TO FIND AMFI HASHTYPE FUNC !!!");
        puts("!!!            HANGING NOW            !!!");
        while (1) {}
    }
    
    void *hash_type_start = (void*) ((uintptr_t) function_find_start(xref_hash_type, (void*) kText_kext->start) - 4);
    if (!hash_type_start) {
        puts("!!! FAILED TO FIND AMFI HASHTYPE FUNC !!!");
        puts("!!!            HANGING NOW            !!!");
        while (1) {}
    }
    
    cpyMem(hash_type_start, "\x20\x00\x80\x52\xc0\x03\x5f\xd6", 8);
    
    // Library validation
    
    // All libraries have a CDHash ;)
    void *csfg_get_cdhash = RESOLVE_TEXT_SYMBOL("_csfg_get_cdhash");
    if (!csfg_get_cdhash) {
        puts("!!! FAILED TO FIND csfg_get_cdhash !!!");
        puts("!!!           HANGING NOW          !!!");
        while (1) {}
    }
    
    cpyMem(csfg_get_cdhash, "\x21\x00\x80\xd2\x41\x00\x00\xf9\xc0\x03\x5f\xd6", 12);
    
    // All libraries are platform binaries ;)
    void *csfg_get_platform_binary = RESOLVE_TEXT_SYMBOL("_csfg_get_platform_binary");
    if (!csfg_get_platform_binary) {
        puts("!!! FAILED TO FIND csfg_get_platform_binary !!!");
        puts("!!!               HANGING NOW               !!!");
        while (1) {}
    }
    
    cpyMem(csfg_get_platform_binary, "\x20\x00\x80\x52\xc0\x03\x5f\xd6", 8);
    
    // Allow invalid pages
    // Kill cs_invalid_page
    // Should be around cs_require_lv
    // Compilers are lazy ;)
    void *cs_require_lv = RESOLVE_TEXT_SYMBOL("_cs_require_lv");
    void *csInvalidPage = find_cs_invalid_page((void*) ((uintptr_t) cs_require_lv - 0x1000), (void*) ((uintptr_t) cs_require_lv + 0x1000));
    cpyMem(csInvalidPage, "\x00\x00\x80\x52\xc0\x03\x5f\xd6", 8);
    
    // FIXME: Do we need this?
    void *isdyldsharedcache = RESOLVE_TEXT_SYMBOL("_vnode_isdyldsharedcache");
    if (!isdyldsharedcache) {
        puts("!!! FAILED TO FIND vnode_isdyldsharedcache !!!");
        puts("!!!               HANGING NOW              !!!");
        while (1) {}
    }
    
    cpyMem(isdyldsharedcache, "\x20\x00\x80\x52\xc0\x03\x5f\xd6", 8);
    
    // FIXME: Do we need this?
    void *canHazDebugger = RESOLVE_TEXT_SYMBOL("_PE_i_can_has_debugger");
    if (!canHazDebugger) {
        puts("!!! FAILED TO FIND PE_i_can_has_debugger !!!");
        puts("!!!              HANGING NOW             !!!");
        while (1) {}
    }
    
    cpyMem(canHazDebugger, "\x00\x00\x80\x52\xc0\x03\x5f\xd6", 8);
    
    // Now do the rootfs r/w patch
    sequence patchSequences_krn[2];
    patchSequences_krn[0].sequence = "root_device";
    patchSequences_krn[0].location = NULL;
    patchSequences_krn[0].size = 11;
    
    patchSequences_krn[1].sequence = "/sbin/launchd";
    patchSequences_krn[1].location = NULL;
    patchSequences_krn[1].size = 13;
    
    sqFound = findSequences((void*) kStrings->start, kStrings->size, &patchSequences_krn[0], 2);
    if (!sqFound) {
        puts("!!! FAILED TO FIND STRING LOCATIONS !!!");
        puts("!!!           HANGING NOW           !!!");
        while (1) {}
    }
    
    // Rename launchd
    cpyMem(patchSequences_krn[1].location, "/iDownload", 11);
    
    // Find call to vfs_rootmountalloc_internal
    uint32_t *rootmount = findRootmountallocCall((void*) kText->start, kTextEnd, patchSequences_krn[0].location);
    if (!rootmount) {
        puts("!!! FAILED TO FIND ROOTMOUNT CALL !!!");
        puts("!!!          HANGING NOW          !!!");
        while (1) {}
    }
    
    uint64_t rootmountAlloc = aarch64_emulate_bl(*rootmount, (uint64_t) rootmount);
    
    // Inject shellcode
    shellcodeLength = (uintptr_t) &rw_root_shellcode_end - (uintptr_t) &rw_root_shellcode_start;
    shellcodeLoc = (void*) ((uintptr_t) shellcodeLoc - shellcodeLength);
    shellcodeLoc = (void*) ((uintptr_t) shellcodeLoc & ~(3ULL));
    
    // Patch it first
    uint64_t *shellcodePatchLoc = (uint64_t*) &rw_root_shellcode_got;
    size_t shellcodeCtr = 0;
    
    shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, rootmountAlloc);
    
    // Now copy it
    cpyMem(shellcodeLoc, &rw_root_shellcode_start, shellcodeLength);
    
    // Replace call to vfs_rootmountalloc_internal
    uint32_t jumpToShellcode = 0x94000000;
    jumpToShellcode |= ((uintptr_t) shellcodeLoc - (uintptr_t) rootmount) >> 2;
    
    // Patch rootmount
    *rootmount = jumpToShellcode;
    
    if (iDownloadPresent) {
        // Find the devfs function
        uint32_t *devfsLoc = (uint32_t*) findDevfsFunc((void*) kText->start, kTextEnd);
        void *kernelMount = (void*) aarch64_emulate_branch(*devfsLoc, (uint64_t) devfsLoc);
        
        // Inject shellcode
        shellcodeLength = (uintptr_t) &devfs_shellcode_end - (uintptr_t) &devfs_shellcode_start;
        shellcodeLoc = (void*) ((uintptr_t) shellcodeLoc - shellcodeLength);
        shellcodeLoc = (void*) ((uintptr_t) shellcodeLoc & ~(3ULL));
        
        // Patch it first
        shellcodePatchLoc = (uint64_t*) &devfs_shellcode_got;
        shellcodeCtr = 0;
        
        // kernel_mount
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, kernelMount);
        // vnode_open
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vnode_open"));
        // vnode_close
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vnode_close"));
        // vfs_context_proc
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vfs_context_proc"));
        // vfs_context_ucred
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vfs_context_ucred"));
        // vn_rdwr
        shellcodePatchLoc[shellcodeCtr++] = OFFSET_64(shellcodeLoc, RESOLVE_TEXT_SYMBOL("_vn_rdwr"));
        // file_buffer
        shellcodePatchLoc[shellcodeCtr++] = (uint64_t) PHYS_TO_VIRT(args, iDownloadLoc);
        // file_size
        shellcodePatchLoc[shellcodeCtr++] = (uint64_t) iDownloadSize;
        
        // Copy it
        cpyMem(shellcodeLoc, &devfs_shellcode_start, shellcodeLength);
        
        // Now patch devfs function
        jumpToShellcode = 0x94000000;
        jumpToShellcode |= ((uintptr_t) shellcodeLoc - (uintptr_t) devfsLoc) >> 2;
        *devfsLoc = jumpToShellcode;
    }
}
