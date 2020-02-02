//
//  PwnUSB_IOKit.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

extension IOKitUSB: PwnUSBDeviceImplementation {
    var nonceDescriptor: String? {
        get {
            if !deviceOpen {
                return nil
            }
            
            let bmRequestType = makeRequestType(direction: .DeviceToHost, type: .Standard, recipient: .Device)
            do {
                let data = try requestFromDevice(requestType: bmRequestType, request: UInt8(kUSBRqGetDescriptor), value: (UInt16(kUSBStringDesc) << 8) | 1 as UInt16, index: 0x409, size: 4096)
                
                return String(data: data.subdata(in: 2..<Int(data[0])), encoding: .utf16LittleEndian)
            } catch {
                return nil
            }
        }
    }
    
    func asyncAbortedTransferToDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, size: Int, abortAfterUSec: UInt32) throws -> UInt32 {
        if !deviceOpen {
            throw IOKitException(message: "Device is not open!")
        }
        
        var dataArray = [UInt8](repeating: 0x41, count: size)
        
        return try dataArray.withUnsafeMutableBufferPointer { (ptr) -> UInt32 in
            let dataArrayPtr = ptr.baseAddress!
            
            var req = IOUSBDevRequestTO(bmRequestType: requestType, bRequest: request, wValue: value, wIndex: index, wLength: UInt16(ptr.count), pData: dataArrayPtr, wLenDone: 0, noDataTimeout: 0, completionTimeout: 0)
            var ready = false
            var done = false
            
            DispatchQueue(label: "USB.PWN").async {
                ready = true
                _ = self.deviceInterface.DeviceRequestTO(self.deviceInterfacePtrPtr, &req)
                // We don't care about what this returns
                done = true
            }
            
            var a = 0
            while !ready {
                usleep(1)
                a += 1
            }
            
            usleep(abortAfterUSec)
            
            let kr = self.deviceInterface.USBDeviceAbortPipeZero(self.deviceInterfacePtrPtr)
            guard kr == KERN_SUCCESS else {
                throw IOKitException(message: "USB abort failed!", kr: kr)
            }
            
            while !done {
                usleep(100)
            }
            
            return req.wLenDone
        }
    }
}
