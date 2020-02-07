//
//  framebuffer.h
//  iStrap
//
//  Created by Linus Henze on 17.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#ifndef framebuffer_h
#define framebuffer_h

#include "definitions.h"
#include "string.h"

extern ssize_t lzss_decompress_to_framebuffer(boot_video *video, int x, int y, int width, uint8_t *src, unsigned int srclen);

void initFramebuffer(boot_args *args);
void drawPixelXY(int x, int y, uint32_t color);
void invertPixel(int x, int y);
void clearScreen(uint8_t r, uint8_t g, uint8_t b);
void rewriteColor(uint8_t or, uint8_t og, uint8_t ob, uint8_t r, uint8_t g, uint8_t b);
void drawChar(int x, int y, char ch);
int printf(const char * restrict format, ...) __printflike(1, 2);
int puts(const char *str);
void findAppleLogo(int *xStart, int *yStart, int *xEnd, int *yEnd);
void checkerboardInterleaved(int startX, int startY, int endX, int endY);

#endif /* framebuffer_h */
