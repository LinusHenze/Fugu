//
//  util.h
//  iStrap
//
//  Created by Linus Henze on 16.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef util_h
#define util_h

#include <stdbool.h>
#include <stdint.h>
#include <stddef.h>

#define LLB_MAGIC      0x11B11B11B11B11B1ULL // 11B -> LLB
#define iBOOT_MAGIC    0x1B0071B0071B0071ULL // 1B007 -> iBoot
#define KERNEL_MAGIC   0x1051051051051051ULL // 105 -> iOS

#define CONFIG_VAR(name, number) uintptr_t name __attribute__((section(".end_data"))) = 0xBAD00001+number;

typedef struct {
    void *sequence;
    size_t size;
    void *location;
} sequence;

bool findSequences(void *start, size_t size, sequence *sequence, size_t sequenceSize);
void cpyMem(void *dst, void *src, size_t len);
bool cmpMem(void *a, void *b, size_t len);

#endif /* util_h */
