//
//  pagetables.h
//  iStrap
//
//  Created by Linus Henze on 16.10.19.
//  Copyright © 2019 Linus Henze. All rights reserved.
//

#ifndef pagetables_h
#define pagetables_h

#include "util.h"

void setup_ttbr1();
uint64_t translate_ttbr0_to_ttbr1(uint64_t address);

#endif /* pagetables_h */
