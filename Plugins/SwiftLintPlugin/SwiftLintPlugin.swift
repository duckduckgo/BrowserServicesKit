//
//  SwiftLintPlugin.swift
//
//  Copyright © 2023 DuckDuckGo. All rights reserved.
//
//  Licensed under the Apache License, Version 2.0 (the "License");
//  you may not use this file except in compliance with the License.
//  You may obtain a copy of the License at
//
//  http://www.apache.org/licenses/LICENSE-2.0
//
//  Unless required by applicable law or agreed to in writing, software
//  distributed under the License is distributed on an "AS IS" BASIS,
//  WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
//  See the License for the specific language governing permissions and
//  limitations under the License.
//

import Foundation
import PackagePlugin

@main
struct SwiftLintPlugin: BuildToolPlugin {

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        // disable output for SPM modules built in RELEASE mode
        guard let target = target as? SwiftSourceModuleTarget,
              target.compilationConditions.contains(.debug) else { return [] }

        let inputFiles = target.sourceFiles(withSuffix: "swift").map(\.path)
        guard !inputFiles.isEmpty else { return [] }

        return try createBuildCommands(
            target: target.name,
            config: target.kind == .test ? .testsSwiftlintConfigFileName : .defaultSwiftlintConfigFileName,
            inputFiles: inputFiles,
            packageDirectory: context.package.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }

    private func createBuildCommands(
        target: String,
        config: String,
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: (String) throws -> PluginContext.Tool
    ) throws -> [Command] {

        // only lint when built from Xcode (disable for CI or xcodebuild)
        guard case .xcode = ProcessInfo().environmentType else { return [] }

        let fm = FileManager()

        let cacheURL = URL(fileURLWithPath: workingDirectory.appending("cache.json").string)
        let outputPath = workingDirectory.appending("output.txt").string

        // if clean build: clear cache
        let buildDir = workingDirectory.removingLastComponent() // BrowserServicesKit
            .removingLastComponent() // browserserviceskit.output
            .removingLastComponent() // plugins
            .removingLastComponent() // SourcePackages
            .removingLastComponent() // DerivedData/DuckDuckGo-xxxx
            .appending("Build")
        if let buildDirContents = try? fm.contentsOfDirectory(atPath: buildDir.string),
           !buildDirContents.contains("Products") {
            print("\(target): SwiftLint: Clean Build")

            try? fm.removeItem(at: cacheURL)
            try? fm.removeItem(atPath: outputPath)
        }

        // read cached data
        var cache = (try? JSONDecoder().decode([String: InputListItem].self, from: Data(contentsOf: cacheURL))) ?? [:]
        // read diagnostics from last pass
        let lastOutput = cache.isEmpty ? "" : (try? String(contentsOfFile: outputPath)) ?? {
            // no diagnostics file – reset
            cache = [:]
            return ""
        }()

        // analyze new/modified files and output cached diagnostics for non-modified files
        var filesToProcess = Set<String>()
        var newCache = [String: InputListItem]()
        for inputFile in inputFiles {
            try autoreleasepool {

                let modified = try inputFile.modified
                if let cacheItem = cache[inputFile.string], modified == cacheItem.modified {
                    // file not modified
                    newCache[inputFile.string] = cacheItem
                    return
                }

                // updated modification date in cache and re-process
                newCache[inputFile.string] = .init(modified: modified)

                filesToProcess.insert(inputFile.string)
            }
        }

        // merge diagnostics from last linter pass into cache
        for outputLint in lastOutput.split(separator: "\n") {
            guard let filePath = outputLint.split(separator: ":", maxSplits: 1).first.map(String.init),
                  !filesToProcess.contains(filePath) else { continue }

            withUnsafeMutablePointer(to: &newCache[filePath]) { itemPtr in
                guard itemPtr.pointee != nil else { return }

                itemPtr.pointee!.diagnostics?.append(String(outputLint)) ?? {
                    itemPtr.pointee!.diagnostics = [String(outputLint)]
                }()
            }
        }

        // collect cached diagnostic messages from cache
        let cachedDiagnostics = newCache.values.reduce(into: [String]()) {
            $0 += $1.diagnostics ?? []
        }

        // We are not producing output files and this is needed only to not include cache files into bundle
        let outputFilesDirectory = workingDirectory.appending("Output")
        try? fm.createDirectory(at: outputFilesDirectory.url, withIntermediateDirectories: true)
        try? fm.removeItem(at: cacheURL.appendingPathExtension("tmp"))
        try? fm.removeItem(atPath: outputPath + ".tmp")

        var result = [Command]()
        if !filesToProcess.isEmpty {
            // write updated cache into temporary file, cache file will be overwritten when linting completes
            try JSONEncoder().encode(newCache).write(to: cacheURL.appendingPathExtension("tmp"))

            var arguments = [
                "lint",
                "--quiet",
                // We always pass all of the Swift source files in the target to the tool,
                // so we need to ensure that any exclusion rules in the configuration are
                // respected.
                "--force-exclude",
                "--cache-path", "\(workingDirectory)",
                // output both to a temporary output cache file
                "--output", "\(outputPath).tmp",
            ]

            // Manually look for configuration files, to avoid issues when the plugin does not execute our tool from the
            // package source directory.
            if let configuration = packageDirectory.firstConfigurationFileInParentDirectories(named: config) {
                arguments.append(contentsOf: ["--config", "\(configuration.string)"])
            }
            arguments += filesToProcess

            result = [
                .prebuildCommand(
                    displayName: "\(target): SwiftLint",
                    executable: try tool("swiftlint").path,
                    arguments: arguments,
                    outputFilesDirectory: outputFilesDirectory
                )
            ]

        } else {
            try JSONEncoder().encode(newCache).write(to: cacheURL)
            try "".write(toFile: outputPath, atomically: false, encoding: .utf8)
        }

        // output cached diagnostic messages from previous run
        result.append(.prebuildCommand(
            displayName: "\(target): SwiftLint: cached \(cacheURL.path)",
            executable: .echo,
            arguments: [cachedDiagnostics.joined(separator: "\n")],
            outputFilesDirectory: outputFilesDirectory
        ))

        if !filesToProcess.isEmpty {
            // when ready put temporary cache and output into place
            result.append(.prebuildCommand(
                displayName: "\(target): SwiftLint: Cache results",
                executable: .mv,
                arguments: ["\(outputPath).tmp", outputPath],
                outputFilesDirectory: outputFilesDirectory
            ))
            result.append(.prebuildCommand(
                displayName: "\(target): SwiftLint: Cache source files modification dates",
                executable: .mv,
                arguments: [cacheURL.appendingPathExtension("tmp").path, cacheURL.path],
                outputFilesDirectory: outputFilesDirectory
            ))
            // duplicate SwiftLint output saved to output.txt to Build Log
            result.append(.prebuildCommand(
                displayName: "\(target): SwiftLint: print output to Build Log",
                executable: .cat,
                arguments: [outputPath],
                outputFilesDirectory: outputFilesDirectory
            ))
        }

        return result
    }
}

#if canImport(XcodeProjectPlugin)

import XcodeProjectPlugin

extension SwiftLintPlugin: XcodeBuildToolPlugin {
    func createBuildCommands(context: XcodePluginContext, target: XcodeTarget) throws -> [Command] {
        guard let product = target.product else { return [] }

        let inputFiles = target.inputFiles.filter {
            $0.type == .source && $0.path.extension == "swift"
        }.map(\.path)

        guard !inputFiles.isEmpty else { return [] }

        return try createBuildCommands(
            target: target.displayName,
            config: product.kind.isUnitTests ? .testsSwiftlintConfigFileName : .defaultSwiftlintConfigFileName,
            inputFiles: inputFiles,
            packageDirectory: context.xcodeProject.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }
}

extension XcodeProduct.Kind {

    var isUnitTests: Bool {
        if case .other("com.apple.product-type.bundle.unit-test") = self { return true }
        return false
    }

}

#endif

extension String {
    static let defaultSwiftlintConfigFileName = ".swiftlint.yml"
    static let testsSwiftlintConfigFileName = ".swiftlint.tests.yml"

    static let debug = "DEBUG"
}
