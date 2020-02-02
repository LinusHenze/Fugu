//
//  util.c
//  iStrap
//
//  Created by Linus Henze on 16.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include <stdbool.h>
#include <stdint.h>
#include <string.h>

#include "util.h"

bool findSequences(void *start, size_t size, sequence *sequence, size_t sequenceSize) {
    if (sequenceSize == 0 || size == 0) {
        return NULL;
    }
    
    void *end = (void*) ((uintptr_t) start + size);
    
    size_t foundCount = 0;
    
    for (; start < end; start++) {
        for (size_t i = 0; i < sequenceSize; i++) {
            if (sequence[i].location != NULL) {
                continue;
            }
            
            bool found = cmpMem(start, sequence[i].sequence, sequence[i].size);
            if (found) {
                foundCount++;
                sequence[i].location = start;
            }
        }
        
        if (foundCount == sequenceSize) {
            return true;
        }
    }
    
    return false;
}

void cpyMem(void *dst, void *src, size_t len) {
    for (size_t i = 0; i < len; i++) {
        ((uint8_t*) dst)[i] = ((uint8_t*) src)[i];
    }
}

bool cmpMem(void *a, void *b, size_t len) {
    for (size_t i = 0; i < len; i++) {
        if (((uint8_t*) a)[i] != ((uint8_t*) b)[i]) {
            return false;
        }
    }
    
    return true;
}

#undef memset

void *memset(void *__b, int __c, size_t __len) {
    for (size_t i = 0; i < __len; i++) {
        *(uint8_t*)__b++ = __c;
    }
    return __b;
}
