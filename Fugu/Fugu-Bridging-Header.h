//
//  Use this file to import your target's public headers that you would like to expose to Swift.
//

#import <stdint.h>

extern int decompress_lzss(u_int8_t *dst, u_int32_t dstlen, u_int8_t *src, u_int32_t srclen);
extern u_int32_t compress_lzss(u_int8_t *dst, u_int32_t dstlen, u_int8_t *src, u_int32_t srclen);
