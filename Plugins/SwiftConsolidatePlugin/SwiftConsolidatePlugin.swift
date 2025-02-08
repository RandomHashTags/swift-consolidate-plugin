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
        guard let directory:String = arguments.first else { return }
        let sourcesFolder:Path = context.package.directory.appending([directory])
        let modules = try FileManager.default.contentsOfDirectory(atPath: sourcesFolder.string)
        for module in modules {
            var filePaths:[String] = []
            let modulePath:Path = sourcesFolder.appending([module])
            try folder(path: modulePath.string, suffixes: [".swift"], filePaths: &filePaths)
            var allCode:String = ""
            for filePath in filePaths {
                if let data:Data = FileManager.default.contents(atPath: filePath), var code:String = String(data: data, encoding: .utf8) {
                    try code.replace(Regex("(@_exported import [a-zA-Z_]+\\s*)"), with: "") // remove exported imports
                    try code.replace(Regex("(import [a-zA-Z_]+\\s*)"), with: "") // remove internal imports
                    try code.replace(Regex("(//\n)"), with: "") // remove empty comments
                    allCode += "\n" + code
                }
            }
            print("Module: \(module);allCode=\n\(allCode)")
        }
    }
    func folder(path: String, suffixes: Set<String>, filePaths: inout [String]) throws {
        let contents:[String] = try FileManager.default.contentsOfDirectory(atPath: path)
        for file in contents {
            let filePath:String = path + "/" + file
            var isDirectory:ObjCBool = false
            if FileManager.default.fileExists(atPath: filePath, isDirectory: &isDirectory) {
                if isDirectory.boolValue {
                    try folder(path: filePath, suffixes: suffixes, filePaths: &filePaths)
                } else {
                    for suffix in suffixes {
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
