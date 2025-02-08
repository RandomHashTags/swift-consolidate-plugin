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
        guard let directory:String = args.first else {
            print("Missing target directory")
            return
        }
        args.removeFirst()
        guard let outputFile:String = args.last else {
            print("Missing outpit file")
            return
        }
        args.removeLast()
        var isEmbedded:Bool = false, isRecursive:Bool = false
        for arg in args {
            switch arg {
            case "--embedded":  isEmbedded = true
            case "--recursive": isRecursive = true
            default: break
            }
        }
        let writeDirectory:Path = context.package.directory.appending([outputFile])
        let settings:ConsolidationSettings = ConsolidationSettings(outputFile: writeDirectory.string, embedded: isEmbedded, recursive: isRecursive)
        
        let fileManager:FileManager = FileManager.default
        let sourcesFolder:Path = context.package.directory.appending([directory])
        let modules = try fileManager.contentsOfDirectory(atPath: sourcesFolder.string)
        var consolidatedData:Data = Data()
        for module in modules {
            var filePaths:[String] = []
            let modulePath:Path = sourcesFolder.appending([module])
            try folder(path: modulePath.string, suffixes: [".swift"], filePaths: &filePaths)
            var allCode:String = ""
            for filePath in filePaths {
                if let data:Data = fileManager.contents(atPath: filePath), var code:String = String(data: data, encoding: .utf8) {
                    for accessControlImport in ["@_exported ", "@_implementationOnly ", "public ", "package ", "internal ", "private ", "fileprivate ", ""] {
                        try code.replace(Regex("(" + accessControlImport + "import [a-zA-Z_]+\\s*)"), with: "") // remove imports
                    }
                    try code.replace(Regex("(//\n)"), with: "") // remove empty comments
                    allCode += "\n" + code
                }
            }
            consolidatedData.append(contentsOf: [UInt8](allCode.utf8))
        }
        if fileManager.createFile(atPath: settings.writeFile, contents: consolidatedData) {
            print("Wrote \(consolidatedData.count) bytes to " + settings.writeFile)
        }
    }
    func folder(
        path: String,
        settings: borrowing ConsolidationSettings,
        filePaths: inout [String]
    ) throws {
        let contents:[String] = try fileManager.contentsOfDirectory(atPath: path)
        for file in contents {
            let filePath:String = path + "/" + file
            var isDirectory:ObjCBool = false
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    if settings.recursive {
                        try folder(path: filePath, settings: settings, filePaths: &filePaths)
                    }
                } else {
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

struct ConsolidationSettings : ~Copyable {
    let outputFile:String
    let suffixes:Set<String>
    let embedded:Bool
    let recursive:Bool
}