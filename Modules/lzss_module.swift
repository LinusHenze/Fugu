//
//  lzss_module.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

class lzssModule: CommandLineModule {
    static var name: String = "lzss"
    static var description: String = "lzss encode a file so that iBoot will like it."
    static var requiredArguments: [CommandLineArgument] = [
        CommandLineArgument(name: "input", description: " The  input file", type: .String),
        CommandLineArgument(name: "output", description: "The output file", type: .String),
    ]
    
    static var optionalArguments: [CommandLineArgument] = [
        CommandLineArgument(longVersion: "--kpp", description: "   KPP file, will be appended to the data", type: .String)
    ]
    
    static func main(arguments: ParsedArguments) -> Never {
        var input = ""
        var output = ""
        for i in arguments.requiredArguments {
            if i.name == "input" {
                input = i.value as! String
            } else if i.name == "output" {
                output = i.value as! String
            } else {
                fail()
            }
        }
        
        var kpp = ""
        for i in arguments.optionalArguments {
            if i.longVersion == "--kpp" {
                kpp = i.value as! String
            } else {
                fail()
            }
        }
        
        let inputData = try? Data(contentsOf: URL(fileURLWithPath: input))
        guard inputData != nil else {
            print("Failed to open input file!")
            exit(-1)
        }
        
        var kppData: Data! = Data()
        if kpp != "" {
            kppData = try? Data(contentsOf: URL(fileURLWithPath: kpp))
            guard kppData != nil else {
                print("Failed to open kpp file!")
                exit(-1)
            }
        }
        
        let result = inputData!.lzssEncoded(extraData: kppData)
        if result == Data() {
            print("LZSS encoding failed!")
            exit(-1)
        }
        
        guard (try? result.write(to: URL(fileURLWithPath: output))) != nil else {
            print("Failed to write to output file!")
            exit(-1)
        }
        
        exit(0)
    }
}
