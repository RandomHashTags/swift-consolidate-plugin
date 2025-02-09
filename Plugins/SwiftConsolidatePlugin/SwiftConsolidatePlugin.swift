//
//  SwiftConsolidatePlugin.swift
//
//
//  Created by Evan Anderson on 2/7/25.
//

import Foundation
import PackagePlugin

@main
struct SwiftConsolidatePlugin : CommandPlugin {
    func performCommand(context: PluginContext, arguments: [String]) async throws {
        var args:[String] = arguments
        let settings:ConsolidationSettings = try loadSettings(context: context, args: &args)
        
        let fileManager:FileManager = FileManager.default
        let sourcesFolder:Path = context.package.directory.appending([settings.sourceDirectory])
        var relativePath:String = ""
        var filePaths:[String] = []
        try folder(absolutePath: sourcesFolder.string, settings: settings, relativePath: &relativePath, filePaths: &filePaths)
        var consolidatedData:Data = Data()
        
        var removeRegex:[String] = []
        var replaceRegex:[(String, String)] = []
        if settings.embedded {
            loadEmbeddedRegex(lang: "swift", remove: &removeRegex, replace: &replaceRegex)
        }
        if settings.forProduction {
            loadProductionRegex(lang: "swift", remove: &removeRegex, replace: &replaceRegex)
        }
        for filePath in filePaths {
            if let data:Data = fileManager.contents(atPath: filePath), var code:String = String(data: data, encoding: .utf8) {
                if let fileExtension:Substring = filePath.split(separator: ".").last {
                    if settings.forProduction {
                        do {
                            try processProduction(fileExtension: fileExtension, string: &code)
                        } catch {
                            print("encountered error while processing production:")
                            throw error
                        }
                    }
                    if settings.embedded {
                        do {
                            try processEmbedded(fileExtension: fileExtension, string: &code)
                        } catch {
                            print("encountered error while processing embedded:")
                            throw error
                        }
                    }
                }
                for regex in removeRegex {
                    do {
                        try code.replace(Regex("(" + regex + ")"), with: "")
                    } catch {
                        print("encountered error while using remove regex \(regex):")
                        throw error
                    }
                }
                for (regex, replacement) in replaceRegex {
                    do {
                        try code.replace(Regex("(" + regex + ")"), with: replacement)
                    } catch {
                        print("encountered error while using replace regex \(regex):")
                        throw error
                    }
                }
                try code.replace(Regex("(//\n)"), with: "") // remove empty comments
                try code.replace(Regex("(\\n\\s+)"), with: ";") // remove remaining unnecessary whitespace
                
                if var stripped:Data = code.data(using: .utf8) {
                    consolidatedData.append(contentsOf: [10]) // \n
                    consolidatedData.append(contentsOf: stripped)
                }
            }
        }
        let writeURL:URL = URL(fileURLWithPath: settings.outputFile)
        try consolidatedData.write(to: writeURL)
        print("Wrote \(consolidatedData.count) bytes to " + settings.outputFile)
    }
    
    func folder(
        absolutePath: String,
        settings: borrowing ConsolidationSettings,
        relativePath: inout String,
        filePaths: inout [String]
    ) throws {
        let contents:[String] = try FileManager.default.contentsOfDirectory(atPath: absolutePath)
        for file in contents {
            let filePath:String = absolutePath + "/" + file
            var isDirectory:ObjCBool = false
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    var relativeDirectoryPath:String = relativePath
                    relativeDirectoryPath += file
                    if !settings.excluded.contains(relativeDirectoryPath) && settings.recursive {
                        relativePath += "/"
                        try folder(absolutePath: filePath, settings: settings, relativePath: &relativeDirectoryPath, filePaths: &filePaths)
                    }
                } else {
                    if !settings.excluded.contains(relativePath + "/" + file) {
                        for suffix in settings.suffixes {
                            if filePath.hasSuffix(suffix) {
                                filePaths.append(filePath)
                                break
                            }
                        }
                    }
                }
            }
        }
    }
}

// MARK: Load Settings
extension SwiftConsolidatePlugin {
    func loadSettings(context: PluginContext, args: inout [String]) throws -> ConsolidationSettings {
        guard let directory:String = args.first else {
            throw ArgumentError.missingSourceDirectory
        }
        args.removeFirst()
        var isEmbedded:Bool = false, isRecursive:Bool = false, forProduction:Bool = false
        var excluded:Set<String> = []
        var lang:String = "swift", langFileExtension:String = lang
        var outputFile:String = "Embedded"
        while !args.isEmpty {
            switch args.first {
            case "--embedded":   isEmbedded = true
            case "--recursive":  isRecursive = true
            case "--production": forProduction = true
            case "--exclude":
                args.removeFirst()
                if let exclude:[String] = args.first?.split(separator: ",").map({ String($0) }) {
                    excluded.formUnion(exclude)
                    args.removeFirst()
                } else {
                    throw ArgumentError.malformedExcludeInput
                }
                continue
            case "--lang":
                args.removeFirst()
                if let l:String = args.first {
                    guard let lfe:String = fileExtension(forLang: l) else {
                        throw ArgumentError.unsupportedLanguage
                    }
                    lang = l
                    langFileExtension = lfe
                    args.removeFirst()
                } else {
                    throw ArgumentError.malformedLangInput
                }
                continue
            case "--output":
                args.removeFirst()
                if let o:String = args.first {
                    outputFile = o
                    args.removeFirst()
                } else {
                    throw ArgumentError.malformedOutputInput
                }
                continue
            default: break
            }
            args.removeFirst()
        }
        let writeDirectory:Path = context.package.directory.appending([outputFile])
        return ConsolidationSettings(
            sourceDirectory: directory,
            outputFile: writeDirectory.string,
            suffixes: ["." + langFileExtension],
            excluded: excluded,
            embedded: isEmbedded,
            recursive: isRecursive,
            forProduction: forProduction
        )
    }
}

// MARK: Lang Source Code File Extension
extension SwiftConsolidatePlugin {
    func fileExtension(forLang lang: String) -> String? {
        switch lang {
        case "swift":
            return lang
        //case "rust":
        //    return "rs"
        default: return nil
        }
    }
}

// MARK: Production Regex
extension SwiftConsolidatePlugin {
    func loadProductionRegex(lang: String, remove: inout [String], replace: inout [(String,String)]) {
        switch lang {
        case "swift": loadSwiftProductionRegex(remove: &remove, replace: &replace)
        default: break
        }
    }
}

// MARK: Swift Production Regex
extension SwiftConsolidatePlugin {
    func loadSwiftProductionRegex(remove: inout [String], replace: inout [(String, String)]) {
        // remove documentation
        remove.append("\\/\\/\\/.+\\s")
        
        // remove comments
        remove.append("\\/\\/.+\\s")
        
        // remove whitespace at the beginning of a line
        remove.append("^\\s+")
        
        // replace whitespace for bitwise operations
        replace.append(("\\s+\\|=\\s+", "|="))
        replace.append(("\\s+>>=\\s+", ">>="))
        replace.append(("\\s+>>\\s+", ">>"))
        replace.append(("\\s+<<=\\s+", "<<="))
        replace.append(("\\s+<<\\s+", "<<"))
        replace.append(("\\s+&\\s+", "&"))
        replace.append(("\\s+\\|\\s+", "|"))
        
        // replace whitespace for equal declarations
        replace.append(("\\s+\\+=\\s+", "+="))
        replace.append(("\\s+\\-=\\s+", "-="))
        replace.append(("\\s+\\*=\\s+", "*="))
        replace.append(("\\s+\\/=\\s+", "/="))
        
        // replace whitespace for standard lib attributes
        let attributes:Set<String> = [
            "discardableResult",
            "dynamicCallable",
            "dynamicMemberLookup",
            "frozen",
            "GKInspectable",
            "inlinable",
            "main",
            "MainActor",
            "nonobjc",
            "NSApplicationMain",
            "NSCopying",
            "NSManaged",
            "objc",
            "objcMembers",
            "preconcurrency",
            "propertyWrapper",
            "resultBuilder",
            "requires_stored_property_inits",
            "testable",
            "UIApplicationMain",
            "unchecked",
            "usableFromInline",
            "warn_unqualified_access",
            
            "autoclosure",
            "Sendable",
            
            "unknown",
            
            "transparent",
            "unsafe_no_objc_tagged_pointer",
            "silgen_name",
        ]
        for attr in attributes {
            replace.append(("@_" + attr + "\\s+", "@_" + attr + " "))
            replace.append(("\\s+@_" + attr + "\\s+", ";@_" + attr + " "))
            replace.append(("@" + attr + "\\s+", "@" + attr + " "))
            replace.append(("\\s+@" + attr + "\\s+", ";@" + attr + " "))
        }
        
        // replace whitespace for conditions
        replace.append(("\\s+===\\s+", "==="))
        replace.append(("\\s+==\\s+", "=="))
        
        // replace whitespace for opening bracket
        replace.append(("\\s+{\\s+", "{"))
        
        // replace whitespace for closing bracket
        replace.append(("\\s+}", "}"))
        
        // replace whitespace for guard else
        replace.append(("\\s+else\\s+{\\s+return nil\\s+}", "else{return nil}"))
        replace.append(("\\s+else\\s+{\\s+return\\s+}", "else{return}"))
        
        // replace whitespace for defer
        replace.append(("defer\\s+", "defer"))
        replace.append(("\\s+defer", ";defer"))
        
        // replace whitespace for break
        //replace["{\\s+break\\s+}"] = "{break}"
        
        // replace whitespace for default keyword
        replace.append(("\\s*+default\\s*+:\\s*+", ";default:"))
        
        // replace whitespace for inout
        replace.append(("inout\\s+\\[", "inout["))
        
        // replace whitespace for return
        replace.append((":\\s+return nil", ":return nil"))
        replace.append(("{\\s+return\\s+", "{"))
        replace.append(("\\s+return", ";return"))
        
        // replace whitespace for switch keyword
        replace.append(("\\s+switch\\s+", ";switch "))
        
        // replace whitespace for case keyword
        replace.append(("{\\s+case\\s*+", "{case"))
        replace.append(("case\\s+\\.", "case."))
        replace.append(("\\)\\s+case", ");case"))
        replace.append(("\\s\\s+case", ";case"))
        replace.append(("\\s+indirect\\s+case", ";indirect case"))
        
        // replace whitespace for colon
        replace.append(("\\s*+:\\s*+", ":"))
        
        // replace whitespace for comma
        replace.append((",\\s+", ","))
        
        // replace whitespace for line feed
        //replace.append(("\n\\s*", ";"))
        
        // correct false positives
        replace.append(("{;", "{"))
        replace.append((":;", ":"))
    }
}

// MARK: Process Production
extension SwiftConsolidatePlugin {
    func processProduction<T: StringProtocol>(fileExtension: T, string: inout String) throws {
        switch fileExtension {
        case "swift": try processSwiftProduction(&string)
        default: break
        }
    }
}

// MARK: Process Swift Production
extension SwiftConsolidatePlugin {
    func processSwiftProduction(_ string: inout String) throws {
        /*let annotations:Regex = try Regex("@\\w+\\s+")
        while let match = string.firstMatch(of: annotations) {
            var substring:Substring = string[match.range]
            while substring.last?.isWhitespace ?? false {
                substring.removeLast()
            }
            substring.append(" ")
            string.replaceSubrange(match.range, with: substring)
        }*/
        
        // replace redundant type annotation
        // TODO: ^^^^^^^^^^^^^^^^^^^^^^^^^^^
    }
}

// MARK: Embedded Regex
extension SwiftConsolidatePlugin {
    func loadEmbeddedRegex(lang: String, remove: inout [String], replace: inout [(String, String)]) {
        switch lang {
        case "swift": loadSwiftEmbeddedRegex(remove: &remove, replace: &replace)
        default: break
        }
    }
}

// MARK: Swift Embedded Regex
extension SwiftConsolidatePlugin {
    func loadSwiftEmbeddedRegex(remove: inout [String], replace: inout [(String, String)]) {
        // TODO: remove !hasFeature(Embedded) compiler directive code block
        // remove imports
        let accessControlImportsRegex:String = "(" + ["@_exported\\s+", "@_implementationOnly\\s+", "public\\s+", "package\\s+", "internal\\s+", "private\\s+", "fileprivate\\s+", "\\s*"].joined(separator: "\\|") + ")?import\\s+\\w+\\s*"
        remove.append(accessControlImportsRegex)
    }
}

// MARK: Process Embedded
extension SwiftConsolidatePlugin {
    func processEmbedded<T: StringProtocol>(fileExtension: T, string: inout String) throws {
        switch fileExtension {
        case "swift": try processSwiftEmbedded(&string)
        default: break
        }
    }
}

// MARK: Process Swift Embedded
extension SwiftConsolidatePlugin {
    func processSwiftEmbedded(_ string: inout String) throws {
        let indirectCase:Regex = try Regex("(\\s+indirect\\s+case\\s+\\w+)")
        //let caseRegex:Regex = try Regex("(\\s+case [a-zA-Z0-9_]+)")
        while let match = string.firstMatch(of: indirectCase)/* ?? string.firstMatch(of: caseRegex)*/ {
            var substring:Substring = string[match.range]
            while substring.first?.isWhitespace ?? false {
                substring.removeFirst()
            }
            substring.insert(";", at: substring.startIndex)
            string.replaceSubrange(match.range, with: substring)
        }
    }
}

// MARK: ConsolidationSettings
struct ConsolidationSettings : ~Copyable {
    let sourceDirectory:String
    let outputFile:String
    let suffixes:Set<String>
    let excluded:Set<String>
    let embedded:Bool
    let recursive:Bool
    let forProduction:Bool
}

// MARK: ArgumentError
enum ArgumentError : Error {
    case missingSourceDirectory
    
    case malformedOutputInput
    case malformedExcludeInput
    case malformedLangInput
    case unsupportedLanguage
}
