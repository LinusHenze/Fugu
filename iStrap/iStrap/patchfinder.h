//
//  patchfinder.h
//  iStrap
//
//  Created by Linus Henze on 22.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef patchfinder_h
#define patchfinder_h

#include "../common/util.h"

void *find_usb_dfu_func(void *start, void *end);

uint64_t aarch64_emulate_adr(uint32_t instruction, uint64_t pc);
uint64_t aarch64_emulate_branch(uint32_t instruction, uint64_t pc);
uint64_t aarch64_emulate_b(uint32_t instr, uint64_t pc);
uint64_t aarch64_emulate_bl(uint32_t instr, uint64_t pc);
uint64_t aarch64_emulate_adrp(uint32_t instruction, uint64_t pc);
bool aarch64_emulate_add_imm(uint32_t instruction, uint32_t *dst, uint32_t *src, uint32_t *imm);
uint64_t aarch64_emulate_adrp_add(uint32_t instruction, uint32_t addInstruction, uint64_t pc);
uint64_t aarch64_emulate_adrp_ldr(uint32_t instruction, uint32_t ldrInstruction, uint64_t pc);
void *find_xref_to(void *start, void *end, uint64_t xrefTo);
void *find_string(void *start, void *end, char *string);
void *find_next_instruction(void *start, void *end, uint32_t instruction);
void *find_next_instruction_threshold(void *start, void *end, uint32_t instruction, size_t threshold);
void *function_find_start(void *location, void *start);
uint64_t get_previous_bl_target(void *searchStart, void *textStart);
uint64_t get_next_bl_target(void *searchStart, void *textEnd);

#endif /* patchfinder_h */
