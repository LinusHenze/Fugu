//
//  iStrap_module.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

var iDownload_noinstall = false
var globalBootArgs: Data? = nil
var globalRestoreFS = false

func iStrap_patchesFor(device: Int) -> [UInt64: [UInt8]] {
    var iDownload = Data()
    if !iDownload_noinstall {
        iDownload = loadResource(name: "shellcode/iDownload.z")
    }
    
    let appendedData = (globalBootArgs ?? Data()) + iDownload
    let iStrap_2x = loadShellcode64(name: "iStrap@2x", constants: [
        // iDownload size
        UInt64(iDownload.count),
        // Boot args size
        UInt64(globalBootArgs?.count ?? 0),
        // Restore FS
        globalRestoreFS ? 1 : 0
    ]) + appendedData
    let iStrap_4x = loadShellcode64(name: "iStrap@4x", constants: [
        // iDownload size
        UInt64(iDownload.count),
        // Boot args size
        UInt64(globalBootArgs?.count ?? 0),
        // Restore FS
        globalRestoreFS ? 1 : 0
    ]) + appendedData
    
    switch device {
    case 0x8010:
        let loader = loadShellcode64(name: "t8010_t8011_iStrap_loader", constants: [])
        
        return [
            // Patch to boot iBoot
            0x100008054: [ 0xE8, 0x07, 0x00, 0x32 ], // orr w8, wzr, #0x3
            
            // Patch for the boot trampoline
            0x1800AC000: [
                0xE2, 0x07, 0x61, 0xB2, // mov x2, #0x180000000
                0x40, 0x00, 0x3F, 0xD6, // blr x2
            ],
            
            // Our loader goes here
            0x180000000: Array<UInt8>(loader),
            
            // Our shellcode goes here
            // Note: This must be 4kB aligned
            0x180001000: Array<UInt8>(iStrap_2x)
        ]
        
    case 0x8011:
        let loader = loadShellcode64(name: "t8010_t8011_iStrap_loader", constants: [])
        
        return [
            // Patch to boot iBoot
            0x100008214: [ 0x68, 0x00, 0x80, 0x52 ], // movz w8, #0x3
            
            // Patch for the boot trampoline
            0x1800AC000: [
                0xE2, 0x07, 0x61, 0xB2, // mov x2, #0x180000000
                0x40, 0x00, 0x3F, 0xD6, // blr x2
            ],
            
            // Our loader goes here
            0x180000000: Array<UInt8>(loader),
            
            // Our shellcode goes here
            // Note: This must be 4kB aligned
            0x180001000: Array<UInt8>(iStrap_4x),
        ]
        
    default:
        return [:]
    }
}

class iStrapModule: CommandLineModule {
    static var name: String = "iStrap"
    static var description: String = "Send iStrap to device and boot kernel.\nCurrently supports: t8010, t8011.\nDevice will be pwned if it is not already."
    
    static var requiredArguments: [CommandLineArgument] = [
        // None
    ]
    
    static var optionalArguments: [CommandLineArgument] = [
        CommandLineArgument(longVersion: "--no-install", description: "Do not install iDownload. Can only be used if it is currently installed.\n                            Will save ~100 KB of RAM.\n                            Note that iDownload will be deleted when booting without the jailbreak.", type: .Flag),
        CommandLineArgument(longVersion: "--boot-args", description: "Set custom boot args.", type: .String),
        CommandLineArgument(shortVersion: "-e", longVersion: "--ecid", description: " The ECID of the device. Will use the first device found if unset.", type: .String),
        CommandLineArgument(longVersion: "--restore-fs", description: "Restore the root filesystem.\n                            This will NOT rename the filesystem snapshot!\n                            This option disables the jailbreak.", type: .Flag)
    ]
    
    static func main(arguments args: ParsedArguments) -> Never {
        var ecid: String? = nil
        var boot_args = ""
        
        for i in args.optionalArguments {
            if i.shortVersion == "-e" {
                ecid = (i.value as! String)
                if ecid!.range(of: "^[0-9a-fA-F]{16}$", options: .regularExpression) == nil {
                    print("ECID must be exactly 16 hex characters!")
                    exit(-1)
                }
            } else if i.longVersion == "--no-install" {
                iDownload_noinstall = i.value as! Bool
            } else if i.longVersion == "--boot-args" {
                boot_args = i.value as! String
            } else if i.longVersion == "--restore-fs" {
                globalRestoreFS = i.value as! Bool
            }
        }
        
        globalBootArgs = boot_args.appending("\u{00}").data(using: .utf8)!
        
        do {
            var iDevice: PwnUSB<IOKitUSB>!
            try StatusIndicator.new("Connecting to iDevice") { (status) -> String in
                iDevice = try PwnUSB<IOKitUSB>(ecid: ecid)
                
                return "Done!"
            }
            
            if !iDevice.pwned {
                print("Device is not in pwned DFU. Exploiting now.")
                try StatusIndicator.new("Exploiting iDevice") { (status) -> String in
                    try iDevice.exploit(status: status)
                    
                    return "PWNED!"
                }
            }
            
            try sendPatches(patches: iDevice.config.iStrapPatches, iDevice: iDevice, doNotReacquire: true)
            
            print("-> iDevice should load iStrap now")
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
