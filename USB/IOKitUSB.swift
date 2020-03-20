//
//  IOKitUSB.swift
//  Fugu
//
//  Created by Linus Henze on 13.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation
import IOKit
import IOKit.usb
import IOKit.usb.IOUSBLib

let kIOUSBDeviceUserClientTypeID: CFUUID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, 0x9d, 0xc7, 0xb7, 0x80, 0x9e, 0xc0, 0x11, 0xD4, 0xa5, 0x4f, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOCFPlugInInterfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, 0xC2, 0x44, 0xE8, 0x58, 0x10, 0x9C, 0x11, 0xD4, 0x91, 0xD4, 0x00, 0x50, 0xE4, 0xC6, 0x42, 0x6F)
let kIOUSBDeviceInterfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, 0x5c, 0x81, 0x87, 0xd0, 0x9e, 0xf3, 0x11, 0xD4, 0x8b, 0x45, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)
let kIOUSBInterfaceInterfaceID: CFUUID = CFUUIDGetConstantUUIDWithBytes(kCFAllocatorDefault, 0x73, 0xc9, 0x7a, 0xe8, 0x9e, 0xf3, 0x11, 0xD4, 0xb1, 0xd0, 0x00, 0x0a, 0x27, 0x05, 0x28, 0x61)

// IOIteratorNext, Swift Style
fileprivate func IOIteratorNext_Swift(_ iterator: io_iterator_t) -> io_service_t? {
    let service = IOIteratorNext(iterator)
    return service != 0 ? service : nil
}

class IOKitException: USBException {
    let kr: kern_return_t?
    
    init(message: String, kr: kern_return_t? = nil) {
        self.kr = kr
        super.init(message: message)
    }
}

final class IOKitUSB: USBDeviceImplementation {
    private var _deviceInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>!
    var deviceInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>! {
        get {
            return _deviceInterfacePtrPtr
        }
    }
    
    var deviceInterface: IOUSBDeviceInterface { get { return deviceInterfacePtrPtr!.pointee!.pointee } }
    
    private var _deviceOpen = false
    var deviceOpen: Bool { get { _deviceOpen } }
    
    // Interesting stuff goes here...
    
    var serialNumber: String? {
        get {
            if !deviceOpen {
                return nil
            }
            
            var serialNumberIndex: UInt8 = 0
            guard deviceInterface.USBGetSerialNumberStringIndex(deviceInterfacePtrPtr, &serialNumberIndex) == KERN_SUCCESS else {
                return nil
            }
            
            let bmRequestType = makeRequestType(direction: .DeviceToHost, type: .Standard, recipient: .Device)
            do {
                let data = try requestFromDevice(requestType: bmRequestType, request: UInt8(kUSBRqGetDescriptor), value: (UInt16(kUSBStringDesc) << 8) | UInt16(serialNumberIndex), index: 0x409, size: 4096)
                
                return String(data: data.subdata(in: 2..<Int(data[0])), encoding: .utf16LittleEndian)
            } catch {
                return nil
            }
        }
    }
    
    func open() throws {
        let kr = deviceInterface.USBDeviceOpen(deviceInterfacePtrPtr)
        if kr == KERN_SUCCESS {
            _deviceOpen = true
            return
        } else {
            throw IOKitException(message: "Failed to open device!", kr: kr)
        }
    }
    
    func openExclusive() throws {
        let kr = deviceInterface.USBDeviceOpenSeize(deviceInterfacePtrPtr)
        if kr == KERN_SUCCESS {
            _deviceOpen = true
            return
        } else {
            throw IOKitException(message: "Failed to open device exclusively!", kr: kr)
        }
    }
    
    func close() {
        if !deviceOpen {
            return
        }
        
        _ = deviceInterface.USBDeviceClose(deviceInterfacePtrPtr)
        _deviceOpen = false
    }
    
    func reset() {
        _ = deviceInterface.USBDeviceReEnumerate(deviceInterfacePtrPtr, 0)
        close()
    }
    
    func sendToDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: Data, timeout: UInt32 = 1) throws {
        _ = try transfer_internal(requestType: requestType, request: request, value: value, index: index, dataOrLength: data, timeout: timeout)
    }
    
    func requestFromDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, size: Int, timeout: UInt32 = 1) throws -> Data {
        return try transfer_internal(requestType: requestType, request: request, value: value, index: index, dataOrLength: size, timeout: timeout)
    }
    
    private func transfer_internal(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, dataOrLength: Any, timeout: UInt32 = 1) throws -> Data {
        if !deviceOpen {
            throw IOKitException(message: "Device is not open!")
        }
        
        var dataArray = [UInt8]()
        if let data = dataOrLength as? Data {
            dataArray = [UInt8](data)
        } else if let size = dataOrLength as? Int {
            dataArray = [UInt8](repeating: 0x41, count: size)
        } else {
            fail()
        }
        
        try dataArray.withUnsafeMutableBufferPointer { (ptr) in
            let dataArrayPtr = ptr.baseAddress!
            
            if timeout != 0 {
                var req = IOUSBDevRequestTO(bmRequestType: requestType, bRequest: request, wValue: value, wIndex: index, wLength: UInt16(ptr.count), pData: dataArrayPtr, wLenDone: 0, noDataTimeout: timeout, completionTimeout: timeout)
                let kr = deviceInterface.DeviceRequestTO(deviceInterfacePtrPtr, &req)
                guard kr == KERN_SUCCESS else {
                    throw IOKitException(message: "Failed to perform USB request!", kr: kr)
                }
            } else {
                var req = IOUSBDevRequest(bmRequestType: requestType, bRequest: request, wValue: value, wIndex: index, wLength: UInt16(ptr.count), pData: dataArrayPtr, wLenDone: 0)
                let kr = deviceInterface.DeviceRequest(deviceInterfacePtrPtr, &req)
                guard kr == KERN_SUCCESS else {
                    throw IOKitException(message: "Failed to perform USB request!", kr: kr)
                }
            }
        }
        
        return Data(dataArray)
    }
    
    // Boring stuff goes here...
    
    static func devicesWith(vid: Int, pid: Int) -> [IOKitUSB] {
        guard var matchingDict = IOServiceMatching(kIOUSBDeviceClassName) as Dictionary? else {
            return []
        }
        
        matchingDict[kUSBVendorName as NSString] = vid as NSNumber  //0x05ac as NSNumber
        matchingDict[kUSBProductName as NSString] = pid as NSNumber //0x1227 as NSNumber
        
        var iterator: io_iterator_t = 0
        
        var kr: kern_return_t = IOServiceGetMatchingServices(kIOMasterPortDefault, matchingDict as CFDictionary, &iterator)
        guard kr == KERN_SUCCESS && iterator != 0 else {
            return []
        }
        
        defer {
            IOObjectRelease(iterator)
        }
        
        var devices = [IOKitUSB]()
        
        while let service = IOIteratorNext_Swift(iterator) {
            defer {
                IOObjectRelease(service)
            }
            
            var pluginPtrPtr = UnsafeMutablePointer<UnsafeMutablePointer<IOCFPlugInInterface>?>(nil)
            var score: sint32 = 0
            
            kr = IOCreatePlugInInterfaceForService(service, kIOUSBDeviceUserClientTypeID, kIOCFPlugInInterfaceID, &pluginPtrPtr, &score)
            guard kr == KERN_SUCCESS, let plugin = pluginPtrPtr?.pointee?.pointee else {
                continue
            }
            
            defer {
                _ = plugin.Release(pluginPtrPtr)
            }
            
            var deviceInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>?
            let deviceInterfaceResult = withUnsafeMutablePointer(to: &deviceInterfacePtrPtr) {
                $0.withMemoryRebound(to: Optional<LPVOID>.self, capacity: 1) {
                    plugin.QueryInterface(pluginPtrPtr, CFUUIDGetUUIDBytes(kIOUSBDeviceInterfaceID), $0)
                }
            }
            
            guard deviceInterfaceResult == KERN_SUCCESS && deviceInterfacePtrPtr?.pointee?.pointee != nil else {
                continue
            }
            
            guard let device = IOKitUSB(deviceInterfacePtrPtr: deviceInterfacePtrPtr) else {
                _ = deviceInterfacePtrPtr!.pointee!.pointee.Release(deviceInterfacePtrPtr)
                continue
            }
            
            devices.append(device)
        }
        
        return devices
    }
    
    private init?(deviceInterfacePtrPtr: UnsafeMutablePointer<UnsafeMutablePointer<IOUSBDeviceInterface>?>!) {
        guard deviceInterfacePtrPtr?.pointee?.pointee != nil else {
            return nil
        }
        
        self._deviceInterfacePtrPtr = deviceInterfacePtrPtr
        
        let nPort = IONotificationPortCreate(kIOMasterPortDefault)
        var source = IONotificationPortGetRunLoopSource(nPort)
        _ = deviceInterface.CreateDeviceAsyncEventSource(deviceInterfacePtrPtr, &source)
        CFRunLoopAddSource(CFRunLoopGetMain(), source?.takeUnretainedValue(), CFRunLoopMode.commonModes)
    }
    
    deinit {
        if deviceOpen {
            close()
        }
        
        _ = deviceInterface.Release(deviceInterfacePtrPtr)
    }
}
