//
//  SimpleUSB.swift
//  Fugu
//
//  Created by Linus Henze on 30.09.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

enum USBRequestDirection: UInt8 {
    case HostToDevice = 0x00
    case DeviceToHost = 0x80
}

enum USBRequestType: UInt8 {
    case Standard = 0x00
    case Class    = 0x20
    case Vendor   = 0x40
    case Reserved = 0x60
}

enum USBRequestRecipient: UInt8 {
    case Device    = 0x00
    case Interface = 0x01
    case Endpoint  = 0x02
    case Other     = 0x03
}

func makeRequestType(direction: USBRequestDirection, type: USBRequestType, recipient: USBRequestRecipient) -> UInt8 {
    return direction.rawValue | type.rawValue | recipient.rawValue
}

class USBException: Error {
    let message: String
    
    init(message: String) {
        self.message = message
    }
}

class SimpleUSB<Implementation: USBDeviceImplementation> {
    private let _device: Implementation
    var device: Implementation { get { _device } }
    
    var serialNumber: String? { get { device.serialNumber } }
    var deviceOpen: Bool { get { device.deviceOpen } }
    
    static func devicesWith(vid: Int, pid: Int) -> [SimpleUSB<Implementation>] {
        let devices_raw = Implementation.devicesWith(vid: vid, pid: pid)
        var devices = [SimpleUSB<Implementation>]()
        
        for dev in devices_raw {
            devices.append(SimpleUSB<Implementation>(device: dev))
        }
        
        return devices
    }
    
    private init(device: Implementation) {
        self._device = device
    }
    
    func open() throws {
        try device.open()
    }
    
    func openExclusive() throws {
        try device.openExclusive()
    }
    
    func reset() {
        device.reset()
    }
    
    func sendToDevice(type: USBRequestType, recipient: USBRequestRecipient, request: UInt8, value: UInt16, index: UInt16, data: Data, timeout: UInt32 = 1) throws {
        let bmRequestType = makeRequestType(direction: .HostToDevice, type: type, recipient: recipient)
        try device.sendToDevice(requestType: bmRequestType, request: request, value: value, index: index, data: data, timeout: timeout)
    }
    
    func requestFromDevice(type: USBRequestType, recipient: USBRequestRecipient, request: UInt8, value: UInt16, index: UInt16, size: Int, timeout: UInt32 = 1) throws -> Data {
        let bmRequestType = makeRequestType(direction: .DeviceToHost, type: type, recipient: recipient)
        return try device.requestFromDevice(requestType: bmRequestType, request: request, value: value, index: index, size: size, timeout: timeout)
    }
    
    func close() {
        device.close()
    }
}
