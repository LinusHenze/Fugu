//
//  utils.swift
//  Fugu
//
//  Created by Linus Henze on 12.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

func initSignalCatchers() {
    func catcher(_ signal: Int32) {
        // Remove ^C from the terminal
        StatusIndicator.globalStatusIndicator?.reprintStatus()
        
        // Make sure the cursor is visible
        print("\u{001b}[?25h")
        fflush(stdout)
        
        // Exit
        exit(-signal)
    }
    
    signal(SIGINT, catcher)
    signal(SIGTERM, catcher)
    signal(SIGQUIT, catcher)
}

func require(_ condition: Bool, function: String = #function, file: String = #file, line: Int = #line) {
    if !condition {
        fail("Assertion failure!", function: function, file: file, line: line)
    }
}

func fail(_ message: String = "<No description provided>", function: String = #function, file: String = #file, line: Int = #line) -> Never {
    let debugInfos = "\n\nDebugging information:\nFunction: \(function)\nFile: \(file)\nLine: \(line)"
    
    // Unhide cursor in case it was hidden
    print("\u{001b}[?25h")
    
    print("\nFatal Error: " + message + debugInfos)
    exit(-SIGILL)
}

func sendPatches<T: USBDeviceImplementation>(patches: [UInt64: [UInt8]], iDevice: PwnUSB<T>, doNotReacquire: Bool = false) throws {
    try StatusIndicator.new("Patching SecureROM") { (status) -> String in
        let patchesCount = patches.keys.count
        if patchesCount == 0 {
            throw PwnException(message: "Fatal: Device is not supported!")
        }
        
        var counter = 1
        for addr in patches.keys {
            let data = patches[addr]!
            status.update("Sending patch \(counter) of \(patchesCount)")
            if !iDevice.memcpy(data: data, to: addr) {
                throw USBException(message: "Failed to send patch!\nThis usually means that the patches have already been applied.")
            }
            
            counter += 1
        }
        
        return "Done!"
    }
    
    StatusIndicator.new("Resetting USB connection") { (status) -> String in
        do {
            try iDevice.dfuAbort(doNotReacquire: doNotReacquire)
        } catch {} // It's ok if this fails
        return "Done!"
    }
}

func loadPayload(name: String) -> Data {
    var url: URL! = Bundle.main.executableURL?.deletingLastPathComponent()
    if url == nil {
        url = URL(fileURLWithPath: FileManager.default.currentDirectoryPath)
    }
    
    guard let payload = try? Data(contentsOf: url.appendingPathComponent("/shellcode/\(name).bin")) else {
        fail("loadPayload: Couldn't find payload \(name).bin!")
    }
    
    return payload
}

// Utils for working with Data objects
extension Data {
    /**
     * Get the raw data of an object
     *
     * - warning: This function is UNSAFE as it could leak pointers. Use with caution!
     *
     * - parameter fromObject: The object whose raw data you would like to get
     */
    init<Type: Any>(fromObject: Type) {
        var value = fromObject
        let valueSize = MemoryLayout.size(ofValue: value)
        
        self = withUnsafePointer(to: &value) { (ptr) -> Data in
            return ptr.withMemoryRebound(to: UInt8.self, capacity: valueSize) { (ptr) -> Data in
                Data(bytes: ptr, count: valueSize)
            }
        }
    }
    
    /**
     * Convert an object to raw data and append
     *
     * - parameter value: The value to convert and append
     */
    mutating func appendGeneric<Type: Any>(value: Type) {
        self.append(Data(fromObject: value))
    }
    
    /**
     * Convert raw data directly into an object
     *
     * - warning: This function is UNSAFE as it could be used to deserialize pointers. Use with caution!
     *
     * - parameter type: The type to convert the raw data into
     */
    func getGeneric<Object: Any>(type: Object.Type) -> Object {
        let data = Array<UInt8>(self)
        return data.withUnsafeBufferPointer { (ptr) -> Object in
            return ptr.baseAddress!.withMemoryRebound(to:Object.self, capacity: MemoryLayout.size(ofValue: type)) { (ptr) -> Object in
                return ptr.pointee
            }
        }
    }
}

extension String {
    func decodeHex() -> Data? {
        if (count % 2) != 0 {
            return nil
        }
        
        var result = Data()
        
        var index = startIndex
        while index != endIndex {
            let x = self[index]
            index = self.index(after: index)
            
            let y = self[index]
            index = self.index(after: index)
            
            guard let byte = UInt8(String(x)+String(y), radix: 16) else {
                return nil
            }
            
            result.appendGeneric(value: byte)
        }
        
        return result
    }
}
