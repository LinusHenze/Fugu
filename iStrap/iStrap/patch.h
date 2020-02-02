//
//  patch.h
//  iStrap
//
//  Created by Linus Henze on 26.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef patch_h
#define patch_h

#include <sys/types.h>

#include "definitions.h"

void applyKernelPatches(boot_args *args, bool iDownloadPresent, void *iDownloadLoc, size_t iDownloadSize);

#endif /* patch_h */
