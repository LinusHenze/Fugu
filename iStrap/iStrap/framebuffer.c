//
//  framebuffer.c
//  iStrap
//
//  Created by Linus Henze on 17.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

#include "framebuffer.h"
#include "../common/util.h"
#include "teletext.h"

#include <stdarg.h>

bool bwInversion = false;
uint32_t bgColor = 0;

int printfCurrentX = 0;
int printfCurrentY = 0;

boot_video *video;

void initFramebuffer(boot_args *args) {
    video = &args->video;
    
    uint32_t *address = (uint32_t*) video->v_baseAddr;
    
    bgColor = address[0];
    
    if (bgColor != 0) {
        // This is a white device
        bwInversion = true;
    }
}

// Pixel functions automatically draw 4x
void drawPixelXY(int x, int y, uint32_t color) {
#if SCALE_FACTOR == 2
    if (x >= video->v_width/2 || y >= video->v_height/2) {
        return;
    }
    
    x *= 2;
    y *= 2;
    
    int rowOffset = video->v_rowBytes/4;
    
    uint32_t *address = (uint32_t*) ((uintptr_t) video->v_baseAddr + ((uintptr_t) y * (uintptr_t) video->v_rowBytes) + ((uintptr_t) x * (uintptr_t) 4));
    for (int i = 0; i < 2; i++) {
        address[0 + (i * rowOffset)] = color;
        address[1 + (i * rowOffset)] = color;
    }
#elif SCALE_FACTOR == 4
    if (x >= video->v_width/4 || y >= video->v_height/4) {
        return;
    }
    
    x *= 4;
    y *= 4;
    
    int rowOffset = video->v_rowBytes/4;
    
    uint32_t *address = (uint32_t*) ((uintptr_t) video->v_baseAddr + ((uintptr_t) y * (uintptr_t) video->v_rowBytes) + ((uintptr_t) x * (uintptr_t) 4));
    for (int i = 0; i < 4; i++) {
        address[0 + (i * rowOffset)] = color;
        address[1 + (i * rowOffset)] = color;
        address[2 + (i * rowOffset)] = color;
        address[3 + (i * rowOffset)] = color;
    }
#else
    #error "Invalid scale factor set!"
#endif
}

void invertPixel(int x, int y) {
#if SCALE_FACTOR == 2
    if (x >= video->v_width/2 || y >= video->v_height/2) {
        return;
    }
    
    x *= 2;
    y *= 2;
    
    int rowOffset = video->v_rowBytes/4;
    
    uint32_t *address = (uint32_t*) ((uintptr_t) video->v_baseAddr + ((uintptr_t) y * (uintptr_t) video->v_rowBytes) + ((uintptr_t) x * (uintptr_t) 4));
    for (int i = 0; i < 2; i++) {
        address[0 + (i * rowOffset)] = ~address[0 + (i * rowOffset)];
        address[1 + (i * rowOffset)] = ~address[1 + (i * rowOffset)];
    }
#elif SCALE_FACTOR == 4
    if (x >= video->v_width/4 || y >= video->v_height/4) {
        return;
    }
    
    x *= 4;
    y *= 4;
    
    int rowOffset = video->v_rowBytes/4;
    
    uint32_t *address = (uint32_t*) ((uintptr_t) video->v_baseAddr + ((uintptr_t) y * (uintptr_t) video->v_rowBytes) + ((uintptr_t) x * (uintptr_t) 4));
    for (int i = 0; i < 4; i++) {
        address[0 + (i * rowOffset)] = ~address[0 + (i * rowOffset)];
        address[1 + (i * rowOffset)] = ~address[1 + (i * rowOffset)];
        address[2 + (i * rowOffset)] = ~address[2 + (i * rowOffset)];
        address[3 + (i * rowOffset)] = ~address[3 + (i * rowOffset)];
    }
#else
    #error "Invalid scale factor set!"
#endif
}

void clearScreen(uint8_t r, uint8_t g, uint8_t b) {
    uint32_t color = (r << 16 | g << 8 | b) << 8;
    uint32_t *videoAddress = (uint32_t*) video->v_baseAddr;
    for (int y = 0; y < video->v_height; y++) {
        for (int x = 0; x < video->v_width; x++) {
            videoAddress[(y * ((int) video->v_rowBytes / 4)) + x] = color;
        }
    }
}

void rewriteColor(uint8_t or, uint8_t og, uint8_t ob, uint8_t r, uint8_t g, uint8_t b) {
    uint32_t color = (r << 16 | g << 8 | b) << 8;
    uint32_t *videoAddress = (uint32_t*) video->v_baseAddr;
    uint32_t bgColor = (or << 16 | og << 8 | ob);
    
    for (int y = 0; y < video->v_height; y++) {
        for (int x = 0; x < video->v_width; x++) {
            if ((videoAddress[(y * ((int) video->v_rowBytes / 4)) + x] >> 8) == bgColor) {
                videoAddress[(y * ((int) video->v_rowBytes / 4)) + x] = color;
            }
        }
    }
}

void drawChar(int x, int y, char ch) {
    if (ch < 0x20 || ch > 0x7F) {
        return;
    }
    
    for (int row = 0; row < CHARSIZE_Y; row++) {
        for (int column = 0; column < CHARSIZE_X; column++) {
            if (teletext[ch - 0x20][row] & (1 << column)) {
                invertPixel(x + ((CHARSIZE_X-1) - column), y + row);
            }
        }
    }
}

#define NEXT_X x += CHARSIZE_X + CHARDISTANCE_X

int printf(const char * restrict text, ...) {
    va_list vl;
    va_start(vl, text);
    
    bool special = false;
    
    int x = printfCurrentX;
    int y = printfCurrentY;
    
    while (*text) {
        if (special) {
            special = false;
            
            switch (*text) {
                case '%':
                    drawChar(x, y, '%'); NEXT_X;
                    break;
                    
                case 'p': {
                    drawChar(x, y, '0'); NEXT_X;
                    drawChar(x, y, 'x'); NEXT_X;
                    
                    uintptr_t ptr = va_arg(vl, uintptr_t);
                    for (int i = 7; i >= 0; i--) {
                        uint8_t cur = (ptr >> (i * 8)) & 0xFF;
                        char first = cur >> 4;
                        if (first >= 0 && first <= 9) {
                            first = first + '0';
                        } else {
                            first = (first - 0xA) + 'A';
                        }
                        
                        char second = cur & 0xF;
                        if (second >= 0 && second <= 9) {
                            second = second + '0';
                        } else {
                            second = (second - 0xA) + 'A';
                        }
                        
                        drawChar(x, y, first);  NEXT_X;
                        drawChar(x, y, second); NEXT_X;
                    }
                    break;
                }
                    
                case 's': {
                    const char *str = va_arg(vl, const char*);
                    if (str == NULL) {
                        str = "<NULL>";
                    }
                    
                    while (*str) {
                        drawChar(x, y, *str); NEXT_X;
                        str++;
                    }
                    break;
                }
                    
                case 'c': {
                    char ch = va_arg(vl, int);
                    drawChar(x, y, ch); NEXT_X;
                    break;
                }
                    
                default:
                    drawChar(x, y, *text); NEXT_X;
                    break;
            }
        } else if (*text == '%') {
            special = true;
        } else {
            if (*text == '\n') {
                y += CHARDISTANCE_Y;
                x = 0;
            } else {
                drawChar(x, printfCurrentY, *text); NEXT_X;
            }
        }
        
        text++;
    }
    
    printfCurrentX = x;
    printfCurrentY = y;
    
    va_end(vl);
    
    return 0;
}

#pragma clang optimize off
int puts(const char *str) {
    return printf("%s\n", str);
}
#pragma clang optimize on

bool rowHasWhite(int y) {
    uint32_t rowSize = (uint32_t) video->v_rowBytes/4;
    uint32_t *address = (uint32_t*) video->v_baseAddr;
    
    for (int x = 0; x < video->v_width; x++) {
        if (bwInversion) {
            if (address[y * rowSize + x] >> 8 == 0) {
                return true;
            }
        } else {
            if (address[y * rowSize + x] >> 8 != 0) {
                return true;
            }
        }
    }
    
    return false;
}

bool columnHasWhite(int x) {
    uint32_t rowSize = (uint32_t) video->v_rowBytes/4;
    uint32_t *address = (uint32_t*) video->v_baseAddr;
    
    for (int y = 0; y < video->v_width; y++) {
        if (bwInversion) {
            if (address[y * rowSize + x] >> 8 == 0) {
                return true;
            }
        } else {
            if (address[y * rowSize + x] >> 8 != 0) {
                return true;
            }
        }
    }
    
    return false;
}

void findAppleLogo(int *xStart, int *yStart, int *xEnd, int *yEnd) {
    int y = 0;
    while (!rowHasWhite(y)) {
        y++;
    }
    
    *yStart = y;
    
    y = video->v_height - 1;
    while (!rowHasWhite(y)) {
        y--;
    }
    
    *yEnd = y;
    
    int x = 0;
    while (!columnHasWhite(x)) {
        x++;
    }
    
    *xStart = x;
    
    x = video->v_width - 1;
    while (!columnHasWhite(x)) {
        x--;
    }
    
    *xEnd = x;
}

//#define CHECKERBOARD_SIZE 9

const uint32_t colorStriping[] = {
    0x000FFC00,
    0x000FFC00,
    0x000FFC00,
    0x3FFFFC00,
    0x3FEAC000,
    0x3F000000,
    0x2F9603FF,
    0x000003FF,
    0x000003FF
};

void checkerboardInterleaved(int startX, int startY, int endX, int endY, uint32_t bgColor) {
    bool startWithBlack = false;
    int outerCounter = 0;
    uint32_t *address = (uint32_t*) video->v_baseAddr;
    uint32_t rowSize = (uint32_t) video->v_rowBytes/4;
    
    uint32_t currentStripeColor = colorStriping[0];
    int currentStripeIndex = 0;
    int stripeY = (endY - startY)/(sizeof(colorStriping)/sizeof(colorStriping[0]));
    int yCounter = 0;
    
    int CHECKERBOARD_SIZE = stripeY/4;
    
    for (int y = startY; y <= endY; y++) {
        if (++outerCounter == CHECKERBOARD_SIZE) {
            outerCounter = 0;
            startWithBlack = !startWithBlack;
            
            if (yCounter >= stripeY) {
                yCounter = 0;
                currentStripeIndex++;
                currentStripeColor = colorStriping[currentStripeIndex];
            }
        }
        
        yCounter++;
        
        bool isBlack = startWithBlack;
        int innerCtr = 0;
        
        for (int x = startX; x <= endX; x++) {
            if (++innerCtr == CHECKERBOARD_SIZE) {
                innerCtr = 0;
                isBlack = !isBlack;
            }
            
            if (address[y * rowSize + x] >> 8 != bgColor) {
                if (isBlack) {
                    address[y * rowSize + x] = 0;
                } else {
                    address[y * rowSize + x] = currentStripeColor;
                }
            }
        }
    }
}
