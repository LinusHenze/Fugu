//
//  pwn.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

class PwnModule: CommandLineModule {
    static var name = "pwn"
    static var description = "Pwn an iDevice using checkm8."
    
    static var requiredArguments: [CommandLineArgument] = [
        // None
    ]
    
    static var optionalArguments: [CommandLineArgument] = [
        CommandLineArgument(shortVersion: "-e", longVersion: "--ecid", description: "The ECID of the device to pwn. Will pwn the first device found if unset.", type: .String),
    ]
    
    static func main(arguments args: ParsedArguments) -> Never {
        var ecid: String? = nil
        
        for i in args.optionalArguments {
            if i.shortVersion == "-e" {
                ecid = (i.value as! String)
                if ecid!.range(of: "^[0-9a-fA-F]{16}$", options: .regularExpression) == nil {
                    print("ECID must be exactly 16 hex characters!")
                    exit(-1)
                }
            }
        }
        
        do {
            var iDevice: PwnUSB<IOKitUSB>!
            try StatusIndicator.new("Connecting to iDevice") { (status) -> String in
                iDevice = try PwnUSB<IOKitUSB>(ecid: ecid)
                
                return "Done!"
            }
            
            try StatusIndicator.new("Exploiting iDevice") { (status) -> String in
                try iDevice.exploit(status: status)
                
                return "PWNED!"
            }
        } catch let e as USBException {
            if StatusIndicator.globalStatusIndicator != nil {
                StatusIndicator.globalStatusIndicator!.failAndExit(msg: e.message)
            } else {
                StatusIndicator.clear()
                print("An exception occured: \(e.message)")
                exit(-1)
            }
        } catch {
            print("An unknown exception occured!")
            exit(-1)
        }
        
        exit(0)
    }
}
