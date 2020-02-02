//
//  pagetables.c
//  iStrap
//
//  Created by Linus Henze on 16.10.19.
//  Copyright © 2019 Linus Henze. All rights reserved.
//

#include "pagetables.h"

extern uintptr_t ttbr1_location;

extern void start();

extern void asm_write_ttbr1(uint64_t address);

#define PHY_ADDRESS_MASK 0x0000FFFFFE000000ULL
#define TTBR1_MIN        0xFFFFFFF000000000ULL

void hook_ttbr0() {
    // We'll make sure our code is RWX
    // Get L2 entry
    
}

void setup_ttbr1() {
    // Setup our ttbr1
    uint64_t *ttbr1 = (uint64_t*) ttbr1_location;
    
    // Clear ttbr1 contents
    for (uint64_t i = 0; i < 2048; i++) {
        ttbr1[i] = 0;
    }
    
    // Write required entries, i.e. us
    ttbr1[0] = ((uint64_t) &start & PHY_ADDRESS_MASK) | 0x625;
    
    // Fully setup ttbr1
    asm_write_ttbr1(ttbr1_location);
}

// 64 Bit only!
// Assumes that address is also the physical address
uint64_t translate_ttbr0_to_ttbr1(uint64_t address) {
    // Hack: Address 0 remains 0
    if (address == 0) {
        return 0;
    }
    
    uint64_t *ttbr1 = (uint64_t*) ttbr1_location;
    
    // What we want to find in our table
    uint64_t target = address & PHY_ADDRESS_MASK;
    
    // We need to walk the ttbr1 pagetable and create mappings if required
    for (uint64_t i = 0; i < 2048; i++) {
        if ((ttbr1[i] & PHY_ADDRESS_MASK) == target) {
            // Found it!
            // Return correct address
            return TTBR1_MIN | (i << 25) | (address & 0x1FFFFFF);
        }
        
        if (ttbr1[i] == 0) {
            // We need to create a new entry
            ttbr1[i] = (address & PHY_ADDRESS_MASK) | 0x625; // RWX
            
            // Now return the address in ttbr1
            return TTBR1_MIN | (i << 25) | (address & 0x1FFFFFF);
        }
    }
    
    // Should NEVER happen
    return 0;
}
