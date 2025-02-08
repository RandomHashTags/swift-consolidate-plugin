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
            print("Missing output file")
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
        let settings:ConsolidationSettings = ConsolidationSettings(outputFile: writeDirectory.string, suffixes: [".swift"], embedded: isEmbedded, recursive: isRecursive)
        
        let fileManager:FileManager = FileManager.default
        let sourcesFolder:Path = context.package.directory.appending([directory])
        var filePaths:[String] = []
        try folder(path: sourcesFolder.string, settings: settings, filePaths: &filePaths)
        var consolidatedData:Data = Data()
        for filePath in filePaths {
            if let data:Data = fileManager.contents(atPath: filePath), var code:String = String(data: data, encoding: .utf8) {
                for accessControlImport in ["@_exported ", "@_implementationOnly ", "public ", "package ", "internal ", "private ", "fileprivate ", ""] {
                    try code.replace(Regex("(" + accessControlImport + "import [a-zA-Z_]+\\s*)"), with: "") // remove imports
                }
                try code.replace(Regex("(//\n)"), with: "") // remove empty comments
                
                if var stripped:Data = code.data(using: .utf8) {
                    consolidatedData.append(contentsOf: [10]) // \n
                    consolidatedData.append(contentsOf: stripped)
                }
            }
        }
        if fileManager.createFile(atPath: settings.outputFile, contents: consolidatedData) {
            print("Wrote \(consolidatedData.count) bytes to " + settings.outputFile)
        }
    }
    func folder(
        path: String,
        settings: borrowing ConsolidationSettings,
        filePaths: inout [String]
    ) throws {
        let contents:[String] = try FileManager.default.contentsOfDirectory(atPath: path)
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
