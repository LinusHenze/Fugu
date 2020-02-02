//
//  definitions.h
//  iStrap
//
//  Created by Linus Henze on 17.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef definitions_h
#define definitions_h

#include <stdint.h>
#include <stdbool.h>

#define CHARSIZE_X    5
#define CHARSIZE_Y    9

#define CHARDISTANCE_X    2
#define CHARDISTANCE_Y    CHARSIZE_Y + 2

#define VIRT_TO_PHYS(args, addr) (((uintptr_t) addr - (uintptr_t) args->virtBase) + (uintptr_t) args->physBase)
#define PHYS_TO_VIRT(args, addr) (((uintptr_t) addr - (uintptr_t) args->physBase) + (uintptr_t) args->virtBase)

#define BOOT_LINE_LENGTH        256

typedef struct boot_video {
    unsigned long    v_baseAddr;    /* Base address of video memory */
    unsigned long    v_display;    /* Display Code (if Applicable) */
    unsigned long    v_rowBytes;    /* Number of bytes per pixel row */
    unsigned long    v_width;    /* Width */
    unsigned long    v_height;    /* Height */
    unsigned long    v_depth;    /* Pixel Depth and other parameters */
} boot_video;

typedef struct boot_args {
    uint16_t        revision;            /* Revision of boot_args structure */
    uint16_t        version;            /* Version of boot_args structure */
    uint64_t        virtBase;            /* Virtual base of memory */
    uint64_t        physBase;            /* Physical base of memory */
    uint64_t        memSize;            /* Size of memory */
    uint64_t        topOfKernelData;        /* Highest physical address used in kernel data area */
    boot_video        video;                /* Video Information */
    uint32_t        machineType;            /* Machine Type */
    void            *deviceTreeP;            /* Base of flattened device tree */
    uint32_t        deviceTreeLength;        /* Length of flattened tree */
    char            commandLine[BOOT_LINE_LENGTH];    /* Passed in command line */
    uint64_t        boot_flags;            /* Misc boot flags*/
} boot_args;

#endif /* definitions_h */
