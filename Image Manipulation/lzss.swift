//
//  lzss.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

fileprivate func lzadler32(buffer: Data) -> UInt32 {
    var lowHalf: UInt = 1
    var highHalf: UInt = 0
    
    for cnt in 0..<buffer.count {
        if (cnt % 5000) == 0 {
            lowHalf  %= 65521
            highHalf %= 65521
        }
        
        lowHalf += UInt(buffer.advanced(by: cnt).getGeneric(type: UInt8.self))
        highHalf += lowHalf
    }
    
    lowHalf  %= 65521
    highHalf %= 65521
    
    return (UInt32(highHalf) << 16) | UInt32(lowHalf)
}

extension Data {
    func lzssEncoded(extraData: Data = Data()) -> Data {
        let adler = lzadler32(buffer: self)
        
        let compressed = self.rawLzssEncoded()
        
        let header = struct_pack(">4s4s4I360x", "comp", "lzss", adler, UInt32(self.count), UInt32(compressed.count), 1 as UInt32)
        
        return header + compressed + extraData
    }
    
    func rawLzssEncoded() -> Data {
        let compressed = self.withUnsafeBytes { (ptr_src) -> Data in
            var data_dst = Data(repeating: 0, count: self.count * 2)
            let compressed_size = data_dst.withUnsafeMutableBytes { (ptr_dst) -> Int in
                let compressed_size = compress_lzss(UnsafeMutablePointer<UInt8>(OpaquePointer(ptr_dst.baseAddress!)), UInt32(ptr_dst.count), UnsafeMutablePointer<UInt8>(OpaquePointer(ptr_src.baseAddress!)), UInt32(ptr_src.count))
                return Int(compressed_size)
            }
            
            return Data(data_dst.prefix(upTo: compressed_size))
        }
        
        return compressed
    }
}
