//
//  USBAbstraction.swift
//  Fugu
//
//  Created by Linus Henze on 13.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

protocol USBDeviceImplementation {
    var serialNumber: String? { get }
    var deviceOpen: Bool { get }
    
    static func devicesWith(vid: Int, pid: Int) -> [Self]
    
    func open() throws
    func openExclusive() throws
    func close()
    
    func reset()
    
    /**
     * Send something to the device
     */
    func sendToDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, data: Data, timeout: UInt32) throws
    
    /**
     * Get something from the device
     */
    func requestFromDevice(requestType: UInt8, request: UInt8, value: UInt16, index: UInt16, size: Int, timeout: UInt32) throws -> Data
}
