//
//  Struct.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

/**
 * Swift equivalent of Python's struct.pack
 * Currently doesn't support every feature, but should be enough
 *
 * Click [here](https://docs.python.org/3/library/struct.html)
 * for the Python documentation.
 *
 * - parameter packStr: A String describing how the data object should be created
 * - parameter params:  The parameters needed to create the data object
 */
func struct_pack(_ packStr: String, _ params: Any...) -> Data {
    var params = params
    var byteOrderSwapped = false
    var repeatCount: UInt? = nil
    
    var result = Data()
    
    func extractParam<X: Any>(ofType: X.Type) -> X {
        guard let param_any = params.first else {
            fail("struct_pack: Not enough parameters")
        }
        
        guard let param = param_any as? X else {
            // Hack for Strings that can be converted to data
            if X.self == Data.self, let param = param_any as? String {
                if let data = param.data(using: .utf8) {
                    params = Array(params.dropFirst())
                    
                    return data as! X
                } else {
                    fail("struct_pack: Failed to encode string \(param) to UTF8 data!")
                }
            }
            
            // Hack for [UInt8] which can be converted to data
            if X.self == Data.self, let param = param_any as? [UInt8] {
                let data = Data(param)
                
                params = Array(params.dropFirst())
                
                return data as! X
            }
            
            fail("struct_pack: Wrong parameter type: Expected \(X.self), got \(type(of: param_any))")
        }
        
        params = Array(params.dropFirst())
        
        return param
    }
    
    func paramLoop<X: Any, Y: Any>(type: X.Type, _ block: ((X) -> Y)) {
        for _ in 0..<(repeatCount ?? 1) {
            let param = extractParam(ofType: type)
            result.appendGeneric(value: block(param))
        }
        
        repeatCount = nil
    }
    
    for c in packStr {
        switch c {
        case "=": fallthrough
        case "@":
            byteOrderSwapped = false
            break
            
        case "<":
            if CFByteOrderGetCurrent() == CFByteOrderLittleEndian.rawValue {
                byteOrderSwapped = false
            } else {
                byteOrderSwapped = true
            }
            break
            
        case ">": fallthrough
        case "!":
            if CFByteOrderGetCurrent() == CFByteOrderBigEndian.rawValue {
                byteOrderSwapped = false
            } else {
                byteOrderSwapped = true
            }
            
        case "0": fallthrough
        case "1": fallthrough
        case "2": fallthrough
        case "3": fallthrough
        case "4": fallthrough
        case "5": fallthrough
        case "6": fallthrough
        case "7": fallthrough
        case "8": fallthrough
        case "9":
            if repeatCount == nil {
                repeatCount = UInt(String(c))
            } else {
                repeatCount! = UInt(String(repeatCount!) + String(c))!
            }
            
            break
            
        case "x":
            for _ in 0..<(repeatCount ?? 1) {
                result.append(contentsOf: [0])
            }
            
            repeatCount = nil
            
        case "b":
            paramLoop(type: Int8.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "B":
            paramLoop(type: UInt8.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "h":
            paramLoop(type: Int16.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "H":
            paramLoop(type: UInt16.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "i": fallthrough
        case "l":
            paramLoop(type: Int32.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "I": fallthrough
        case "L":
            paramLoop(type: UInt32.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "q":
            paramLoop(type: Int64.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "Q":
            paramLoop(type: UInt64.self) { (param) in
                return byteOrderSwapped ? param.byteSwapped : param
            }
            
        case "s":
            var param = extractParam(ofType: Data.self)
            
            if repeatCount == nil {
                result.append(param)
            } else {
                if param.count > repeatCount! {
                    fail("struct_pack: Data object has size bigger than the repeat count!")
                }
                
                if param.count < repeatCount! {
                    param = param + Data(repeating: 0, count: Int(repeatCount! - UInt(param.count)))
                }
                
                result.append(param)
            }
            
            repeatCount = nil
            
        default:
            fail("struct_pack: Unknown character \(c)!")
        }
    }
    
    return result
}
