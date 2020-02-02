//
//  deviceTree.h
//  iStrap
//
//  Created by Linus Henze on 22.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef deviceTree_h
#define deviceTree_h

#include "../common/util.h"
#include "definitions.h"

void dt_add_ramdisk(boot_args *args, uintptr_t ramdisk, size_t ramdiskSize);

#define kPropNameLength    32

typedef struct DeviceTreeNodeProperty {
    char        name[kPropNameLength];    // NUL terminated property name
    uint32_t    length;        // Length (bytes) of folloing prop value
    uint8_t     data[];
    //  unsigned long    value[1];    // Variable length value of property
    // Padded to a multiple of a longword?
} DeviceTreeNodeProperty;

typedef struct OpaqueDTEntry {
    uint32_t        nProperties;    // Number of props[] elements (0 => end)
    uint32_t        nChildren;    // Number of children[] elements
    DeviceTreeNodeProperty    props[];// array size == nProperties
    //  DeviceTreeNode    children[];    // array size == nChildren
} DeviceTreeNode;

typedef struct __attribute__((packed)) DTMemoryEntry {
    char        name[kPropNameLength];    // NUL terminated property name
    uint32_t    length;        // Length (bytes) of folloing prop value
    uintptr_t   start;
    size_t      size;
} DTMemoryEntry;

DeviceTreeNode *dt_node_find_child(DeviceTreeNode *root, const char *name);
DeviceTreeNodeProperty *dt_node_lookup_property(DeviceTreeNode *node, const char *name);
uint32_t dt_size_of_all_props(DeviceTreeNode *node);
DTMemoryEntry *dt_lookup_memory_map(boot_args *args, char *name);

#endif /* deviceTree_h */
