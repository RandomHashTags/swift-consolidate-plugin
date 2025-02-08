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
        
        var removeRegex:Set<String> = []
        var replaceRegex:[String:String] = [:]
        if settings.embedded {
            // remove imports
            for accessControlImport in ["@_exported ", "@_implementationOnly ", "public ", "package ", "internal ", "private ", "fileprivate ", ""] {
                removeRegex.insert(accessControlImport + "import [a-zA-Z_]+\\s*")
            }
        }
        if settings.forProduction {
            loadProductionRegex(lang: "swift", remove: &removeRegex, replace: &replaceRegex)
        }
        let processEmbeddedLogic:(inout String) throws -> Void = processEmbedded(lang: "swift")
        for filePath in filePaths {
            if let data:Data = fileManager.contents(atPath: filePath), var code:String = String(data: data, encoding: .utf8) {
                try processEmbeddedLogic(&code)
                for regex in removeRegex {
                    try code.replace(Regex("(" + regex + ")"), with: "")
                }
                for (regex, replacement) in replaceRegex {
                    try code.replace(Regex("(" + regex + ")"), with: replacement)
                }
                try code.replace(Regex("(//\n)"), with: "") // remove empty comments
                
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

// MARK: Lang Source Code File Extension
extension SwiftConsolidatePlugin {
    func fileExtension(forLang lang: String) -> String? {
        switch lang {
        case "c", "swift":
            return lang
        case "rust":
            return "rs"
        default: return nil
        }
    }
}

// MARK: Production Regex
extension SwiftConsolidatePlugin {
    func loadProductionRegex(lang: String, remove: inout Set<String>, replace: inout [String:String]) {
        switch lang {
        case "swift": loadSwiftProductionRegex(remove: &remove, replace: &replace)
        default: break
        }
    }
}

// MARK: Swift Production Regex
extension SwiftConsolidatePlugin {
    func loadSwiftProductionRegex(remove: inout Set<String>, replace: inout [String:String]) {
        // remove documentation
        remove.insert("\\/\\/\\/.+\\s")
        // remove comments
        remove.insert("\\/\\/.+\\s")
        
        // replace whitespace for bitwise operations
        replace["\\s+\\|=\\s+"] = "|="
        replace["\\s+>>=\\s+"] = ">>="
        replace["\\s+>>\\s+"] = ">>"
        replace["\\s+<<=\\s+"] = "<<="
        replace["\\s+<<\\s+"] = "<<"
        replace["\\s+&\\s+"] = "&"
        replace["\\s+\\|\\s+"] = "|"
        
        // replace whitespace for equal declarations
        replace["\\s+\\+=\\s+"] = "+="
        replace["\\s+\\-=\\s+"] = "-="
        replace["\\s+\\*=\\s+"] = "*="
        replace["\\s+\\/=\\s+"] = "/="
        
        // replace whitespace for standard lib annotations
        replace["@inlinable\\s+"] = "@inlinable "
        replace["@usableFromInline\\s+"] = "@usableFromInline "
        
        // replace whitespace for conditions
        replace["\\s+===\\s+"] = "==="
        replace["\\s+==\\s+"] = "=="
        
        // replace whitespace for guard else
        replace["\\s+else\\s+{\\s+return nil\\s+}"] = "else{return nil}"
        replace["\\s+else\\s+{\\s+return\\s+}"] = "else{return}"
        
        // replace whitespace for defer
        replace["defer\\s+{\\s+"] = "defer{"
        
        // replace whitespace for break
        replace["{\\s+break\\s+}"] = "{break}"
        
        // replace default whitespace
        replace["\\s*+default\\s*+:\\s*+"] = ";default:"
        
        // replace return nil whitespace
        replace[":\\s+return nil"] = ":return nil"
        
        // replace case whitespace
        replace["case\\s+\\."] = "case."
        
        // replace colon whitespace
        replace["\\s*+:\\s*+"] = ":"
    }
}

// MARK: Process Embedded
extension SwiftConsolidatePlugin {
    func processEmbedded(lang: String) -> (inout String) throws -> Void {
        switch lang {
        case "swift": return processSwiftEmbedded
        default: return { _ in }
        }
    }
}

// MARK: Process Swift Embedded
extension SwiftConsolidatePlugin {
    func processSwiftEmbedded(_ string: inout String) throws {
        // TODO: remove compiler directives not available for embedded
        
        let indirectCase:Regex = try Regex("(\\s+indirect case [a-zA-Z0-9_]+)")
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
