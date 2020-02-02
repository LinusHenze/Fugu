//
//  loader.c
//  iStrap Loader
//
//  Created by Linus Henze on 19.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "../common/util.h"

#define IMAGE_MAX_SIZE 0x100000ULL

uint64_t now_loading = iBOOT_MAGIC;
uint64_t iBoot_base = iBOOT_MAGIC;
uint64_t iBoot_end = iBOOT_MAGIC;

extern void main_iStrap(void *image, void *args, void *iBoot_base, void *iBoot_end);

extern void iBoot_hook_sequence();
extern void ttbr0_write_sequence_el1();
extern void sctlr_write_sequence_el1();

extern void iBoot_hook();
extern void asm_ttbr0_hook_shellcode();
extern void custom_sctlr_write_sequence_el1();

extern void *find_ttbr0_entry_end(void *start, uint64_t *ttbr0);
extern void *asm_read_ttbr0();

void patch_iBoot(void *image, void *args) {
    sequence sequences[3];
    
    // Patch iBoot trampoline
    sequences[0].sequence = (void*) &iBoot_hook_sequence;
    sequences[0].size = 12;
    sequences[0].location = NULL;
    
    // Hook write ttbr0 function
    sequences[1].sequence = (void*) &ttbr0_write_sequence_el1;
    sequences[1].size = 12;
    sequences[1].location = NULL;
    
    // Replace write sctlr function
    sequences[2].sequence = (void*) &sctlr_write_sequence_el1;
    sequences[2].size = 12;
    sequences[2].location = NULL;
    
    bool result = findSequences(image, IMAGE_MAX_SIZE, sequences, 3);
    if (!result) {
        return;
    }
    
    // Patch iBoot trampoline
    cpyMem(sequences[0].location, (void*) &iBoot_hook, 8);
    
    // Hook ttbr0 code
    cpyMem(sequences[1].location, (void*) &asm_ttbr0_hook_shellcode, 12);
    
    // Replace sctlr function
    cpyMem(sequences[2].location, (void*) &custom_sctlr_write_sequence_el1, 20);
}

void main_loader(void *image, void *args) {
    if (now_loading == iBOOT_MAGIC) {
        // iBoot stuff
        patch_iBoot(image, args);
        now_loading = KERNEL_MAGIC;
        
        iBoot_base = (uint64_t) image;
    } else if (now_loading == KERNEL_MAGIC) {
        // Kernel, launch iStrap
        main_iStrap(image, args, (void*) iBoot_base, (void*) iBoot_end);
    } else {
        // WTF?!
        return;
    }
}
