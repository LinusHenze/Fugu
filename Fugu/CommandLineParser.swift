//
//  CommandLineParser.swift
//  Fugu
//
//  Created by Linus Henze on 14.10.19.
//  Copyright © 2019/2020 Linus Henze. All rights reserved.
//

import Foundation

enum CommandLineArgumentTypes {
    case String
    case Int
    case UInt
    case Flag
}

/**
 * A command line argument
 */
class CommandLineArgument: Equatable {
    let name:         String // This name will only be shown for required arguments that do not have a short or long version
    let shortVersion: String
    let longVersion:  String
    let description:  String
    let type:         CommandLineArgumentTypes
    var value:        AnyObject?
    
    static func == (lhs: CommandLineArgument, rhs: CommandLineArgument) -> Bool {
        return lhs.description == rhs.description
    }
    
    init(name: String, description: String, type: CommandLineArgumentTypes) {
        self.name = name
        self.shortVersion = ""
        self.longVersion = ""
        self.description = description
        self.type = type
    }
    
    init(shortVersion: String, description: String, type: CommandLineArgumentTypes) {
        self.name = ""
        self.shortVersion = shortVersion
        self.longVersion = ""
        self.description = description
        self.type = type
    }
    
    init(longVersion: String, description: String, type: CommandLineArgumentTypes) {
        self.name = ""
        self.shortVersion = ""
        self.longVersion = longVersion
        self.description = description
        self.type = type
    }
    
    init(shortVersion: String, longVersion: String, description: String, type: CommandLineArgumentTypes) {
        self.name = ""
        self.shortVersion = shortVersion
        self.longVersion = longVersion
        self.description = description
        self.type = type
    }
}

struct ParsedArguments {
    let requiredArguments: [CommandLineArgument]
    let optionalArguments: [CommandLineArgument]
}

/**
 * Create a new command line module
 *
 * Create a new command line module which can be accessed by running this app as:
 *
 * `app <module name> <arguments>`
 */
protocol CommandLineModule {
    static var name: String { get }
    static var description: String { get }
    static var requiredArguments: [CommandLineArgument] { get }
    static var optionalArguments: [CommandLineArgument] { get }
    
    static func main(arguments: ParsedArguments) -> Never
}

fileprivate func typeToString(type: CommandLineArgumentTypes) -> String {
    switch type {
    case .String:
        return "value"
        
    case .Int: fallthrough
    case .UInt:
        return "number"
        
    case .Flag:
        return ""
    }
}

fileprivate func getModuleDescription(module: CommandLineModule.Type, appName: String) -> String {
    var result = ""
    result += "\t\(module.name)\n"
    result += "\t\tUsage:\n"
    var usageString = "\(appName) \(module.name)"
    for i in module.requiredArguments {
        let type = typeToString(type: i.type)
        
        if i.shortVersion != "" {
            usageString += " [\(i.shortVersion) <\(type)>]"
        } else if i.longVersion != "" {
            usageString += " [\(i.longVersion) <\(type)>]"
        } else if i.name != "" {
            usageString += " [\(i.name)]"
        } else {
            fail("getModuleDescription: XXX - This shouldn't happen")
        }
    }
    
    if module.optionalArguments.count != 0 {
        usageString += " <optional parameters>"
    }
    
    result += "\t\t\t\(usageString)\n"
    result += "\t\tDescription:\n"
    result += "\t\t\t\(module.description.replacingOccurrences(of: "\n", with: "\n\t\t\t"))\n"
    if module.requiredArguments.count != 0 {
        result += "\t\tRequired Parameters:\n"
        for i in module.requiredArguments {
            result += "\t\t\t"
            
            let type = typeToString(type: i.type)
            if i.shortVersion != "" {
                result += "\(i.shortVersion)"
            }
            
            if i.longVersion != "" {
                if i.shortVersion != "" {
                    result += ", \(i.longVersion)"
                } else {
                    result += "\(i.longVersion)"
                }
            }
            
            if i.name != "" && i.shortVersion == "" && i.longVersion == "" {
                if type != "" {
                    result += "[\(i.name) <\(type)>]"
                } else {
                    result += "[\(i.name)]"
                }
            } else {
                if type != "" {
                    result += " <\(type)>"
                }
            }
            
            result += "\t\(i.description)\n"
        }
    }
    
    if module.optionalArguments.count != 0 {
        result += "\t\tOptional Parameters:\n"
        for i in module.optionalArguments {
            result += "\t\t\t"
            
            let type = typeToString(type: i.type)
            if i.shortVersion != "" {
                result += "\(i.shortVersion)"
            }
            
            if i.longVersion != "" {
                if i.shortVersion != "" {
                    result += ", \(i.longVersion)"
                } else {
                    result += "\(i.longVersion)"
                }
            }
            
            if i.name != "" && i.shortVersion == "" && i.longVersion == "" {
                fail("getModuleDescription: A short or long version must be set for optional parameters, not a name.")
            } else {
                if type != "" {
                    result += " <\(type)>"
                }
            }
            
            result += "\t\(i.description)\n"
        }
    }
    
    return result
}

fileprivate func printUsage(modules: [CommandLineModule.Type]) -> Never {
    var appName = "app"
    if let appNameReal = getprogname() {
        appName = String(cString: appNameReal)
    }
    
    print("Usage: \(appName) <action> <parameters>")
    print("Where action can be one of:")
    
    var descriptions = ""
    for i in 0..<modules.count {
        descriptions += getModuleDescription(module: modules[i], appName: appName)
        if i != modules.count - 1 {
            descriptions += "\n"
        }
    }
    
    print(descriptions.replacingOccurrences(of: "\t", with: "    "))
    
    exit(-1)
}

fileprivate func parseInput(input: String, type: CommandLineArgumentTypes) -> AnyObject? {
    switch type {
    case .String:
        return input as AnyObject
    case .Int:
        if let value = Int(input) {
            return value as AnyObject
        }
        
        if input.starts(with: "0x") {
            if let value = Int(input[input.index(after: input.index(after: input.startIndex))...]) {
                return value as AnyObject
            }
        }
        
        return nil
    case .UInt:
        return UInt(input) as AnyObject
    case .Flag:
        return true as AnyObject
    }
}

fileprivate func parseArgumentsFor(module: CommandLineModule.Type, allModules: [CommandLineModule.Type]) -> Never {
    var parsedRequiredArguments = Array<CommandLineArgument>()
    var parsedOptionalArguments = Array<CommandLineArgument>()
    
    var nextIsValue         = false
    var wasRequiredArgument = false
    
    var counter = 2
    
    for arg in CommandLine.arguments[2...] {
        if nextIsValue {
            nextIsValue = false
            
            let argument = wasRequiredArgument ? parsedRequiredArguments.last! : parsedOptionalArguments.last!
            let type = argument.type
            
            guard let value = parseInput(input: arg, type: type) else {
                print("Value passed to argument \(CommandLine.arguments[counter]) is not a \(typeToString(type: type))\n")
                printUsage(modules: allModules)
            }
            
            argument.value = value
            
            continue
        }
        
        var found = false
        
        // Maybe a required argument?
        for i in module.requiredArguments {
            if arg == i.shortVersion || arg == i.longVersion {
                if let index = parsedRequiredArguments.firstIndex(of: i) {
                    parsedRequiredArguments.remove(at: index)
                }
                
                parsedRequiredArguments.append(i)
                if i.type != .Flag {
                    nextIsValue = true
                    wasRequiredArgument = true
                } else {
                    parsedRequiredArguments.last!.value = true as AnyObject
                }
                
                found = true
                
                break
            }
        }
        
        if found {
            counter += 1
            continue
        }
        
        // Maybe an optional argument?
        for i in module.optionalArguments {
            if arg == i.shortVersion || arg == i.longVersion {
                if let index = parsedOptionalArguments.firstIndex(of: i) {
                    parsedOptionalArguments.remove(at: index)
                }
                
                parsedOptionalArguments.append(i)
                if i.type != .Flag {
                    nextIsValue = true
                    wasRequiredArgument = false
                } else {
                    parsedOptionalArguments.last!.value = true as AnyObject
                }
                
                found = true
                
                break
            }
        }
        
        if found {
            counter += 1
            continue
        }
        
        // Maybe the direct argument to a required argument?
        for i in module.requiredArguments {
            if i.name != "" {
                if i.value == nil {
                    guard let value = parseInput(input: arg, type: i.type) else {
                        print("Value passed to argument \(i.name) is not a \(typeToString(type: i.type))\n")
                        printUsage(modules: allModules)
                    }
                    
                    i.value = value
                    
                    parsedRequiredArguments.append(i)
                    
                    found = true
                    
                    break
                }
            }
        }
        
        if found {
            counter += 1
            continue
        }
        
        print("Unknown argument \(arg)!\n")
        printUsage(modules: allModules)
    }
    
    // A value is still missing...
    if nextIsValue {
        print("Value for \(CommandLine.arguments.last!) is missing!\n")
        printUsage(modules: allModules)
    }
    
    if parsedRequiredArguments.count != module.requiredArguments.count {
        print("Not enough arguments!\n")
        printUsage(modules: allModules)
    }
    
    // Invoke block!
    module.main(arguments: ParsedArguments(requiredArguments: parsedRequiredArguments, optionalArguments: parsedOptionalArguments))
}

func parseCommandLine(modules: [CommandLineModule.Type]) -> Never {
    if CommandLine.arguments.count < 2 {
        printUsage(modules: modules)
    }
    
    for i in modules {
        if CommandLine.arguments[1] == i.name {
            parseArgumentsFor(module: i, allModules: modules)
        }
    }
    
    printUsage(modules: modules)
}
