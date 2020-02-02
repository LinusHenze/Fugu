//
//  PwnUSBDeviceImplementation.swift
//  Fugu
//
//  Created by Linus Henze on 02.11.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

protocol PwnUSBDeviceImplementation: USBDeviceImplementation {
    var nonceDescriptor: String? { get }
    
    func asyncAbortedTransferToDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, size: Int, abortAfterUSec: UInt32) throws -> UInt32 /* Number of Bytes sent */
}
