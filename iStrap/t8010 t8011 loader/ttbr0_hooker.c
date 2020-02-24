//
//  ttbr0_hooker.c
//  iStrap Loader
//
//  Created by Linus Henze on 17.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "../common/util.h"

extern uint64_t asm_get_el();
extern void asm_write_ttbr0(uintptr_t);
extern void start(void);

extern uint64_t now_loading;
extern uint64_t iBoot_base;
extern uint64_t iBoot_end;

void *find_ttbr0_entry_end(void *start, uint64_t *ttbr0);

#define L2_ENTRY_MASK 0x3FF
#define L3_ENTRY_MASK 0x3FF

#define ADDR_L2_ENTRY(addr) ((((uintptr_t) addr) >> 25) & L2_ENTRY_MASK)
#define ADDR_L3_ENTRY(addr) ((((uintptr_t) addr) >> 14) & L2_ENTRY_MASK)

void patch_entry(uint64_t *ttbr0, size_t L2_idx, size_t L3_idx) {
    uint64_t l2Entry = ttbr0[L2_idx];
    switch (l2Entry & 3) {
        case 1:
            // Block -> Adjust permissions
            l2Entry &= ~0x600000000000C0ULL;
            ttbr0[L2_idx] = l2Entry;
            break;
            
        case 3: {
            // L3 Table
            uint64_t *L3_table = (uint64_t*) (l2Entry & 0xFFFFFFFFC000);
            l2Entry &= 0x7800000000000000ULL;
            ttbr0[L2_idx] = l2Entry;
            size_t L3_idx_start = L3_idx;
            
            for (size_t L3_idx = L3_idx_start; L3_idx < L3_idx_start+32; L3_idx++) {
                uint64_t l3Entry = L3_table[L3_idx];
                switch (l3Entry & 3) {
                    case 3:
                        // Block -> Adjust permissions
                        l3Entry &= ~0x600000000000C0ULL;
                        L3_table[L3_idx] = l3Entry;
                        break;
                        
                    default:
                        // Unmapped, create mapping
                        l3Entry = ((uint64_t) L2_idx << 25) | ((uint64_t) L3_idx << 14) | 0x627;
                        L3_table[L3_idx] = l3Entry;
                        break;
                }
            }
            break;
        }
            
        default:
            // Unmapped, create mapping
            l2Entry = ((uint64_t) L2_idx << 25) | 0x625;
            ttbr0[L2_idx] = l2Entry;
            break;
    }
}

void ttbr0_hooker(uint64_t *ttbr0) {
    uint64_t el = asm_get_el();
    
    if (el == 1) {
        // Normal, 16kb page size, start with L2
        // Add entries for us
        patch_entry(ttbr0, ADDR_L2_ENTRY(&start), ADDR_L3_ENTRY(&start));
        
        // Add entries for the "Secure Memory"
        patch_entry(ttbr0, ADDR_L2_ENTRY(0x820000000ULL), ADDR_L3_ENTRY(0x820000000ULL));
        
        if (now_loading == KERNEL_MAGIC) {
            iBoot_end = (uint64_t) find_ttbr0_entry_end((void*) iBoot_base, (void*) ttbr0);
        }
    } else if (el == 3) {
        // EL3, 4kb page size, start with L1
    } else {
        // LOL, wtf?
        return;
    }
    
    // Write ttbr0
    asm_write_ttbr0((uintptr_t) ttbr0);
}

void *find_ttbr0_entry_end(void *start, uint64_t *ttbr0) {
    size_t L2_idx = ADDR_L2_ENTRY(&start);
    uint64_t l2Entry = ttbr0[L2_idx];
    switch (l2Entry & 3) {
        case 1:
            // Block
            return (void*) ((uintptr_t) start + 0x2000000);
            
        case 3: {
            // L3 Table
            uint64_t *L3_table = (uint64_t*) (l2Entry & 0xFFFFFFFFC000);
            size_t L3_idx_start = ADDR_L3_ENTRY(&start);
            
            for (size_t L3_idx = L3_idx_start; L3_idx < 2048; L3_idx++) {
                uint64_t l3Entry = L3_table[L3_idx];
                switch (l3Entry & 3) {
                    case 3:
                        break;
                        
                    default:
                        return (void*) ((uintptr_t) start + (0x4000 * L3_idx));
                }
            }
            
            return (void*) ((uintptr_t) start + 0x2000000);
        }
            
        default:
            // Unmapped
            return start;
    }
}
