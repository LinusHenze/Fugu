//
//  main.c
//  iStrap
//
//  Created by Linus Henze on 16.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "../common/util.h"
#include "definitions.h"
#include "framebuffer.h"
#include "deviceTree.h"
#include "patch.h"
#include "miniz/miniz.h"

CONFIG_VAR(iDownload_size, 0)
CONFIG_VAR(boot_args_size, 1)
CONFIG_VAR(force_restore_fs, 2)

extern void appended_data_start();

#undef memset
#undef memcpy

#pragma clang optimize off

void simple_sleep() {
    for (uint64_t i = 0; i < 2048*2732*50; i++) {
        ;
    }
}

void __attribute__((section(".text.boot"))) main_iStrap(void *image, boot_args *args, void *iBoot_base, void *iBoot_end) {
    initFramebuffer(args);
    
    int lgStartX, lgStartY, lgEndX, lgEndY = 0;
    findAppleLogo(&lgStartX, &lgStartY, &lgEndX, &lgEndY);
    checkerboardInterleaved(lgStartX, lgStartY, lgEndX, lgEndY);
    
    puts("====================================");
    puts("         Welcome to iStrap!         ");
    puts("     iStrap kernel bootstrapper     ");
    puts("     Part of the Fugu Jailbreak     ");
    puts("");
    puts("   Copyright 2019/2020 Linus Henze  ");
    puts("   This is free software, see the   ");
    puts("  LICENSE file for more information ");
    puts("");
    puts("   If you paid for this software,   ");
    puts("           you got scammed          ");
    puts("====================================");
    puts("");
    
    if (boot_args_size && *((char*) &appended_data_start) != 0) {
        puts(  "[*] Setting boot-args...");
        printf("[*] Current boot-args: \"%s\"\n", args->commandLine);
        
        cpyMem(args->commandLine, (void*) &appended_data_start, boot_args_size);
        
        char *cmdLine = args->commandLine;
        while (*cmdLine) {
            if (*cmdLine == '-' && cmdLine[1] == 'v') {
                args->video.v_display = 0;
                break;
            }
            
            cmdLine++;
        }
        
        printf("[*] New boot-args: \"%s\"\n", args->commandLine);
        puts(  "[+] Boot-args set!");
    }
    
    void   *iDownload_loc = NULL;
    size_t iDownload_realSize = 0;
    
    if (iDownload_size != 0) {
        puts("[*] Decompressing iDownload...");
        
        void *iDownload_start = (void*) ((uintptr_t) &appended_data_start + boot_args_size);
        
        memset((void*) args->topOfKernelData, 0, 0x6400000);
        iDownload_realSize = tinfl_decompress_mem_to_mem((void*) args->topOfKernelData, 0x6400000, iDownload_start, iDownload_size, TINFL_FLAG_PARSE_ZLIB_HEADER);
        if (iDownload_realSize == TINFL_DECOMPRESS_MEM_TO_MEM_FAILED) {
            // OOOPS
            puts("!!! Failed to decompress !!!");
            puts("!!!      HANGING NOW     !!!");
            while (1) {}
        }
        
        iDownload_loc = (void*) args->topOfKernelData;
        args->topOfKernelData = (args->topOfKernelData + iDownload_realSize + 0x3000) & ~(0x3fffULL);
    }
    
    puts("[*] Applying kernel patches...");
    
    applyKernelPatches(args, iDownload_size != 0, iDownload_loc, iDownload_realSize, force_restore_fs != 0);
    
    puts("[+] Successfully patched kernel!");
    
    puts("[+] All done! Ready to boot!");
    
    puts("[*] Booting in a few seconds...");
    
    simple_sleep();
}

#pragma clang optimize on
