//
//  deviceTree.c
//  iStrap
//
//  Created by Linus Henze on 22.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include <string.h>

#include "deviceTree.h"
#include "definitions.h"
#include "framebuffer.h"

#undef strcmp
#undef memcpy
#undef memset
#undef memmove

#define ROUND_3(ptr) (((uintptr_t) (ptr) + 3) & ~(3ULL))
#define next_prop(curProp) ((DeviceTreeNodeProperty*) ROUND_3((uintptr_t) curProp + (curProp->length & 0xFFFFFF) + sizeof(DeviceTreeNodeProperty)))
#define next_child(node) ((DeviceTreeNode*) ((uintptr_t) node + sizeof(DeviceTreeNode) + dt_size_of_all_props(node)))

boot_args *cachedArgs;

void dt_add_ramdisk(boot_args *args, uintptr_t ramdisk, size_t ramdiskSize) {
    cachedArgs = args;
    
    uintptr_t dt = VIRT_TO_PHYS(args, args->deviceTreeP);
    uintptr_t end = dt + args->deviceTreeLength;
    
    size_t newPropSize = ROUND_3(32 + 4 + 16);
    
    // Insert entry
    DeviceTreeNode *chosen = dt_node_find_child((DeviceTreeNode*) dt, "chosen");
    if (!chosen) {
        puts("[-] DT: chosen not found!");
        return;
    }
    
    DeviceTreeNode *memoryMap = dt_node_find_child(chosen, "memory-map");
    if (!memoryMap) {
        puts("[-] DT: memory-map not found!");
        return;
    }
    
    // Insert RAMDisk property
    DeviceTreeNode *nextNode = next_child(memoryMap);
    
    // Copy the child to the end
    // Overlapping buffers, must use memmove
    memmove((void*) ((uintptr_t) nextNode + newPropSize), nextNode, (uintptr_t) end - (uintptr_t) nextNode);
    
    // Insert the property
    DeviceTreeNodeProperty *ramdiskProp = (DeviceTreeNodeProperty*) nextNode;
    memset(&ramdiskProp->name, 0, 32);
    memcpy(&ramdiskProp->name, "RAMDisk", 8);
    ramdiskProp->length = 16;
    uint64_t *adr = (uint64_t*) &ramdiskProp->data[0];
    adr[0] = ramdisk;
    adr[1] = ramdiskSize;
    
    // Increase number of properties
    memoryMap->nProperties += 1;
    
    // Increase the size
    args->deviceTreeLength += newPropSize;
    
    // Update DeviceTree property
    DeviceTreeNodeProperty *dtProp = dt_node_lookup_property(memoryMap, "DeviceTree");
    if (!dtProp) {
        puts("[-] DT: DeviceTree not found!");
        return;
    }
    
    adr = (uint64_t*) &dtProp->data[0];
    adr[1] += newPropSize;
    
    puts("[+] DT: Added RAMDisk entry!");
}

DeviceTreeNode *dt_node_find_child(DeviceTreeNode *root, const char *name) {
    DeviceTreeNodeProperty *prop = dt_node_lookup_property(root, "name");
    if (prop != NULL) {
        if (strcmp((const char *) prop->data, name) == 0) {
            return root;
        }
    }
    
    uint32_t childCount = root->nChildren;
    
    DeviceTreeNode *child = (DeviceTreeNode*) ((uintptr_t) &root->nChildren + sizeof(uint32_t) + dt_size_of_all_props(root) + 3);
    child = (DeviceTreeNode*) ((uintptr_t) child & ~(3ULL));
    
    while (childCount--) {
        prop = dt_node_lookup_property(child, "name");
        if (prop != NULL) {
            if (strcmp((const char *) prop->data, name) == 0) {
                return child;
            }
        }
        
        child = next_child(child);
    }
    
    return NULL;
}

DeviceTreeNodeProperty *dt_node_lookup_property(DeviceTreeNode *node, const char *name) {
    uint32_t propCount = node->nProperties;
    
    DeviceTreeNodeProperty *prop = (DeviceTreeNodeProperty*) &node->props;
    
    while (propCount--) {
        if (strcmp(prop->name, name) == 0) {
            return prop;
        }
        
        prop = next_prop(prop);
    }
    
    return NULL;
}

uint32_t dt_size_of_all_props(DeviceTreeNode *node) {
    uint32_t size = 0;
    
    uint32_t propCount = node->nProperties;
    
    DeviceTreeNodeProperty *prop = (DeviceTreeNodeProperty*) ((uintptr_t) &node->nChildren + sizeof(uint32_t));
    
    while (propCount--) {
        // Only need to round length, prop is already rounded
        uint32_t len = (uint32_t) ROUND_3((prop->length & 0xFFFFFF) + sizeof(DeviceTreeNodeProperty));
        size += len;
        prop = (DeviceTreeNodeProperty*) ((uintptr_t) prop + len);
    }
    
    // Round the size
    return (uint32_t) ROUND_3(size);
}

DTMemoryEntry *dt_lookup_memory_map(boot_args *args, char *name) {
    uintptr_t dt = VIRT_TO_PHYS(args, args->deviceTreeP);
    
    DeviceTreeNode *chosen = dt_node_find_child((DeviceTreeNode*) dt, "chosen");
    if (!chosen) {
        return NULL;
    }
    
    DeviceTreeNode *memoryMap = dt_node_find_child(chosen, "memory-map");
    if (!memoryMap) {
        return NULL;
    }
    
    return (DTMemoryEntry*) dt_node_lookup_property(memoryMap, name);
}
