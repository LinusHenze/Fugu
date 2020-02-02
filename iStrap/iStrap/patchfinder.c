//
//  patchfinder.c
//  iStrap
//
//  Created by Linus Henze on 22.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "patchfinder.h"
#include <string.h>

#undef strcmp

#define GUARD_VAR(var) if (!(var)) { return NULL; }

/**
 * Find the DFU download function to download RAM disks
 */
void *find_usb_dfu_func(void *start, void *end) {
    void *dfu_str = find_string(start, end, "Apple Mobile Device (DFU Mode)");
    GUARD_VAR(dfu_str)
    
    void *dfu_str_xref = find_xref_to(start, end, (uint64_t) dfu_str);
    GUARD_VAR(dfu_str_xref)
    
    // Now test if this is the wrong function
    void *test = find_next_instruction(dfu_str_xref, end, 0xd65f03c0); // Find ret
    GUARD_VAR(test)
    if ((test - dfu_str_xref) < 0x10) {
        // Wrong function!
        // Find the second, right one
        dfu_str_xref = find_xref_to(dfu_str_xref + 4, end, (uint64_t) dfu_str);
        GUARD_VAR(dfu_str_xref)
    }
    
    // Ok, found it
    // Now find the start
    void *usb_init_wc = function_find_start(dfu_str_xref, start);
    GUARD_VAR(usb_init_wc)
    
    // Find init_usb
    void *usb_init = find_xref_to(start, end, (uint64_t) usb_init_wc);
    GUARD_VAR(usb_init)
    
    // Find function start
    usb_init = function_find_start(usb_init, start);
    GUARD_VAR(usb_init)
    
    // Now find xrefs
    // We should find an xref to a branch island
    void *island = find_xref_to(start, end, (uint64_t) usb_init);
    GUARD_VAR(island)
    
    void *download = find_xref_to(start, end, (uint64_t) island);
    if (download == NULL) {
        // Nope, not the island
        island = find_xref_to(island + 4, end, (uint64_t) usb_init);
        GUARD_VAR(island)
        download = find_xref_to(start, end, (uint64_t) island);
        GUARD_VAR(download)
    }
    
    // Check if this is the real donwload func
    void *download_start = function_find_start(download, start);
    GUARD_VAR(download_start)
    while ((download - download_start) > 0x40) {
        // Wrong!
        download = find_xref_to(download + 4, end, (uint64_t) island);
        GUARD_VAR(download)
        download_start = function_find_start(download, start);
        GUARD_VAR(download_start)
    }
    
    return download_start;
}

/**
 * Emulate an adr instruction at the given pc value
 * Returns adr destination
 */
uint64_t aarch64_emulate_adr(uint32_t instruction, uint64_t pc) {
    // Check that this is an adr instruction
    if ((instruction & 0x9F000000) != 0x10000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0xFFFFE0) >> 3;
    imm |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        // Sign extend
        imm |= 0xFFE00000;
    }
    
    // Emulate
    return pc + imm;
}

/**
 * Emulate a b/bl instruction at the given pc value
 * Returns branch destination
 */
uint64_t aarch64_emulate_branch(uint32_t instruction, uint64_t pc) {
    // Check that this is a branch instruction
    if ((instruction & 0x7C000000) != 0x14000000) {
        return 0;
    }
    
    int32_t imm = (instruction & 0x3FFFFFF) << 2;
    if (instruction & 0x2000000) {
        // Sign extend
        imm |= 0xFC000000;
    }
    
    // Emulate
    return pc + imm;
}

uint64_t aarch64_emulate_b(uint32_t instr, uint64_t pc) {
    // Make sure this is a normal branch
    if ((instr & 0x80000000) != 0) {
        return 0;
    }
    
    // Checks that this is a b
    return aarch64_emulate_branch(instr, pc);
}

uint64_t aarch64_emulate_bl(uint32_t instr, uint64_t pc) {
    // Make sure this is not a normal branch
    if ((instr & 0x80000000) != 0x80000000) {
        return 0;
    }
    
    // Checks that this is a bl
    return aarch64_emulate_branch(instr, pc);
}

/**
 * Emulate an adrp instruction at the given pc value
 * Returns adrp destination
 */
uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc) {
    // Check that this is an adrp instruction
    if ((instruction & 0x9F000000) != 0x90000000) {
        return 0;
    }
    
    // Calculate imm from hi and lo
    int32_t imm_hi_lo = (instruction & 0xFFFFE0) >> 3;
    imm_hi_lo |= (instruction & 0x60000000) >> 29;
    if (instruction & 0x800000) {
        // Sign extend
        imm_hi_lo |= 0xFFE00000;
    }
    
    // Build real imm
    int64_t imm = ((int64_t) imm_hi_lo << 12);
    
    // Emulate
    return (pc & ~(0xFFFULL)) + imm;
}

bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm) {
    // Check that this is an add instruction with immediate
    if ((instruction & 0xFF000000) != 0x91000000) {
        return 0;
    }
    
    int32_t imm12 = (instruction & 0x3FFC00) >> 10;
    
    uint8_t shift = (instruction & 0xC00000) >> 22;
    switch (shift) {
        case 0:
            *imm = imm12;
            break;
            
        case 1:
            *imm = imm12 << 12;
            break;
            
        default:
            return false;
    }
    
    *dst = instruction & 0x1F;
    *src = (instruction >> 5) & 0x1F;
    
    return true;
}

/**
 * Emulate an adrp and add instruction at the given pc value
 * Returns destination
 */
uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    uint32_t addDst;
    uint32_t addSrc;
    uint32_t addImm;
    if (!aarch64_emulate_add_imm(addInstruction, &addDst, &addSrc, &addImm)) {
        return 0;
    }
    
    if ((instruction & 0x1F) != addSrc) {
        return 0;
    }
    
    // Emulate
    return adrp_target + (uint64_t) addImm;
}

/**
 * Emulate an adrp and ldr instruction at the given pc value
 * Returns destination
 */
uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc) {
    uint64_t adrp_target = aarch64_emulate_adrp(instruction, pc);
    if (!adrp_target) {
        return 0;
    }
    
    if ((instruction & 0x1F) != ((ldrInstruction >> 5) & 0x1F)) {
        return 0;
    }
    
    if ((ldrInstruction & 0xFFC00000) != 0xF9400000) {
        return 0;
    }
    
    uint32_t imm12 = ((ldrInstruction >> 10) & 0xFFF) << 3;
    
    // Emulate
    return adrp_target + (uint64_t) imm12;
}

/**
 * Find an xref to an address
 *
 * \param start Start address
 * \param end End address
 * \param xrefTo The address for which a xref should be found
 */
void *find_xref_to(void *start, void *end, uint64_t xrefTo) {
    uint32_t *cur = (uint32_t*) start;
    
    while (cur < (uint32_t*) end) {
        uint32_t inst = *cur;
        uint64_t xref = aarch64_emulate_adr(inst, (uint64_t) cur);
        if (!xref) {
            xref = aarch64_emulate_adrp_add(inst, *(cur+1), (uint64_t) cur);
            if (!xref) {
                xref = aarch64_emulate_branch(inst, (uint64_t) cur);
            }
        }
        
        if (xref == xrefTo) {
            return cur;
        }
        
        cur++;
    }
    
    return NULL;
}

/**
 * Find a string
 * \param start Start address
 * \param end End address
 * \param string The string to find
 */
void *find_string(void *start, void *end, char *string) {
    void *cur = start;
    
    while (cur < end) {
        if (strcmp(cur, string) == 0) {
            return cur;
        }
        
        cur++;
    }
    
    return NULL;
}

void *find_next_instruction(void *start, void *end, uint32_t instruction) {
    uint32_t *cur = (uint32_t*) start;
    
    while (cur < (uint32_t*) end) {
        if (*cur == instruction) {
            return cur;
        }
        
        cur++;
    }
    
    return NULL;
}

void *find_next_instruction_threshold(void *start, void *end, uint32_t instruction, size_t threshold) {
    uint32_t *cur = (uint32_t*) start;
    
    for (size_t c = 0; cur < (uint32_t*) end && c < threshold; c++) {
        if (*cur == instruction) {
            return cur;
        }
        
        cur++;
    }
    
    return NULL;
}

/**
 * Find the start of a function
 * \param location An instruction inside the function
 * \param start Start of the image where the function is in
 */
void *function_find_start(void *location, void *start) {
    // We want to find add x29, sp, #0x????
    uint32_t *cur = (uint32_t*) location;
    
    while (cur >= (uint32_t*) start) {
        uint32_t inst = *cur;
        if ((inst & 0xFF0003FF) == 0x910003FD) {
            // Now check the stp instructions before
            do {
                cur--;
                
                inst = *cur;
                if ((inst & 0xFF4003E0) != 0xA90003E0) {
                    return (void*) ((uintptr_t) cur + 4);
                }
            } while (cur >= (uint32_t*) start);
            
            return NULL;
        }
        
        cur--;
    }
    
    return NULL;
}

uint64_t get_previous_bl_target(void *searchStart, void *textStart) {
    uint32_t *cur = (uint32_t*) searchStart;
    
    while (cur >= (uint32_t*) textStart) {
        uint64_t target = aarch64_emulate_bl(*cur, (uint64_t) cur);
        if (target) {
            return target;
        }
        
        cur--;
    }
    
    return 0;
}

uint64_t get_next_bl_target(void *searchStart, void *textEnd) {
    uint32_t *cur = (uint32_t*) searchStart;
    
    while (cur < (uint32_t*) textEnd) {
        uint64_t target = aarch64_emulate_bl(*cur, (uint64_t) cur);
        if (target) {
            return target;
        }
        
        cur++;
    }
    
    return 0;
}
