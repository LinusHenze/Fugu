//
//  string_and_mem.c
//  iStrap
//
//  Created by Linus Henze on 20.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include <string.h>
#include <stdint.h>
#include <stdarg.h>

#undef memcpy
#undef memmove
#undef strncpy

void *memmove(void *dst, const void *src, size_t n) {
    if (dst == src) {
        return dst;
    }
    
    if (dst < src) {
        return memcpy(dst, src, n);
    }
    
    uint8_t *d = (uint8_t*) dst + (n-1);
    uint8_t *s = (uint8_t*) src + (n-1);
    
    while (n--) {
        *d-- = *s--;
    }
    
    return dst;
}

void *memcpy(void *dst, const void *src, size_t n) {
    uint8_t *d = (uint8_t*) dst;
    uint8_t *s = (uint8_t*) src;
    
    while (n--) {
        *d++ = *s++;
    }
    
    return dst;
}

char *strncpy(char *dst, const char *src, size_t n) {
    char *d = dst;
    char *s = (char*) src;
    
    while (n-- && *s) {
        *d++ = *s++;
    }
    
    return dst;
}

size_t strlen(const char * str) {
    size_t len = 0;
    while (*str++) {
        len++;
    }
    
    return len;
}

int strcmp(const char *s1, const char *s2) {
    while (*s1 == *s2 && *s1) {
        s1++;
        s2++;
    }
    
    return *s1 - *s2;
}
