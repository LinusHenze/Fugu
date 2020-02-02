//
//  StatusIndicator.swift
//  Fugu
//
//  Created by Linus Henze on 12.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

/**
 * StatusIndicator: A class to show status indicators on the screen
 *
 * - Important: Only one status StatusIndicator is allowed at any given time. Nesting is not supported.
 *
 * **Example**
 *
 * Let's assume we're connecting to a server over SSL and want to inform the user, that we're currently doing
 * the SSL handshake.
 *
 * We could do that using this code:
 *
 * ```
 * StatusIndicator.new("Connecting") { (status) -> String in
 *     ...
 *     status.update("TLS handshake") // Show status update
 *     performTLSHandshake()
 *     ...
 *     return "Done" // Show final update
 * }
 * ```
 *
 * On the screen, this will be shown:
 *
 *      Connecting: TLS handshake
 *
 * And after the connection has been established, it will look like this:
 *
 *      Connecting: Done
 */
class StatusIndicator {
    private static var _globalStatusIndicator: StatusIndicator?
    static var globalStatusIndicator: StatusIndicator? { get { _globalStatusIndicator } }
    
    private var message = ""
    private var currentStatus  = ""
    
    /**
     * Create a new StatusIndicator that will be passed to a block
     *
     * - parameter msg:   The message that will be shown before each update
     * - parameter block: The block to execute. First parameter will be the StatusIndicator, return value will be
     *                    the last update shown
     */
    static func new(_ msg: String, _ block: ((StatusIndicator) throws -> String)) rethrows {
        if globalStatusIndicator != nil {
            fail("StatusIndicator may not be nested!")
        }
        
        let update = StatusIndicator(msg)
        
        _globalStatusIndicator = update
        
        // Hide cursor
        print("\u{001b}[?25l", terminator: "")
        fflush(stdout)
        
        let result = try block(update)
        
        // Show cursor
        print("\u{001b}[?25h", terminator: "")
        fflush(stdout)
        
        update.final(msg: result)
        
        _globalStatusIndicator = nil
    }
    
    /**
     * Shows a status update
     *
     * - parameter status: The update to show. Passing an empty string will clear the current update.
     */
    func update(_ status: String) {
        StatusIndicator.clear()
        
        if status.count > 0 {
            currentStatus = status
            print(message + ": " + status, terminator: "")
            fflush(stdout)
        } else {
            currentStatus = ""
            print(message, terminator: "")
            fflush(stdout)
        }
    }
    
    /**
     * Prints the current status again
     */
    func reprintStatus() {
        update(currentStatus)
    }
    
    func failAndExit(msg: String, exitValue: Int32 = -1) -> Never {
        final(msg: "FAILED!")
        print(msg)
        
        // Show cursor
        print("\u{001b}[?25h", terminator: "")
        
        exit(exitValue)
    }
    
    /**
     * Clears the current line
     */
    static func clear() {
        if isatty(STDOUT_FILENO) == 1 {
            print("\u{001b}[2K\r", terminator: "")
            fflush(stdout)
        } else {
            print("") // Newline, can't do inplace status updates
        }
    }
    
    /**
     * The private init function
     *
     * - parameter msg: The message that will be shown before each update
     */
    private init(_ msg: String) {
        message = msg
        update("")
    }
    
    /**
     * Finalizes the status, then writes a new line
     */
    private func final(msg: String) {
        update(msg)
        print("")
    }
}
