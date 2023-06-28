//
//  SwiftLintPlugin.swift
//  DuckDuckGo
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

struct InputListItem: Codable {

    let modified: Date
    var diagnostics: [String]?

    init(modified: Date) {
        self.modified = modified
    }

}

@main
struct SwiftLintPlugin: BuildToolPlugin {
    enum ConfigKind {
        case `default`
        case tests
    }

    func createBuildCommands(context: PluginContext, target: Target) async throws -> [Command] {
        guard let sourceTarget = target as? SourceModuleTarget else {
            return []
        }
        return try createBuildCommands(
            config: sourceTarget.kind == .test ? .testsSwiftlintConfigFileName : .defaultSwiftlintConfigFileName,
            inputFiles: sourceTarget.sourceFiles(withSuffix: "swift").map(\.path),
            packageDirectory: context.package.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }

    private func createBuildCommands(
        config: String,
        inputFiles: [Path],
        packageDirectory: Path,
        workingDirectory: Path,
        tool: (String) throws -> PluginContext.Tool
    ) throws -> [Command] {
        if inputFiles.isEmpty {
            // Don't lint anything if there are no Swift source files in this target
            return []
        }

        // read cached data
        let cacheURL = URL(fileURLWithPath: workingDirectory.appending("cache.json").string)
        var cache = (try? JSONDecoder().decode([String: InputListItem].self, from: Data(contentsOf: cacheURL))) ?? [:]

        // read diagnostics from last pass
        let outputPath = workingDirectory.appending("output.txt").string
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
        try? FileManager.default.removeItem(at: cacheURL.appendingPathExtension("tmp"))
        try? FileManager.default.removeItem(atPath: outputPath + ".tmp")

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
                // output both to build log and to temporary output cache file
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
                    displayName: "SwiftLint",
                    executable: try tool("swiftlint").path,
                    arguments: arguments,
                    outputFilesDirectory: outputFilesDirectory
                )
            ]

        } else {
            try JSONEncoder().encode(newCache).write(to: cacheURL)
            try "".write(toFile: outputPath, atomically: false, encoding: .utf8)
        }


        // output cached diagnostic messages
        result.append(.prebuildCommand(
            displayName: "SwiftLint: cached \(cacheURL.path)",
            executable: Path("/bin/echo"),
            arguments: [cachedDiagnostics.joined(separator: "\n")],
            outputFilesDirectory: outputFilesDirectory
        ))

        if !filesToProcess.isEmpty {
            // when ready put temporary cache and output into place
            result.append(.prebuildCommand(
                displayName: "Cache SwiftLint results",
                executable: .mv,
                arguments: ["\(outputPath).tmp", outputPath],
                outputFilesDirectory: outputFilesDirectory
            ))
            result.append(.prebuildCommand(
                displayName: "Cache source files modification dates for SwiftLint",
                executable: .mv,
                arguments: [cacheURL.appendingPathExtension("tmp").path, cacheURL.path],
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
        let inputFilePaths = target.inputFiles
            .filter { $0.type == .source && $0.path.extension == "swift" }
            .map(\.path)
        return try createBuildCommands(
            config: target.product?.kind == .other(.unitTestsKind) ? .testsSwiftlintConfigFileName : .defaultSwiftlintConfigFileName,
            inputFiles: inputFilePaths,
            packageDirectory: context.xcodeProject.directory,
            workingDirectory: context.pluginWorkDirectory,
            tool: context.tool(named:)
        )
    }
}

extension XcodeProduct.Kind: Equatable {
    public static func == (lhs: XcodeProduct.Kind, rhs: XcodeProduct.Kind) -> Bool {
        switch lhs {
        case .application: if case .application = rhs { return true }
        case .executable: if case .executable = rhs { return true }
        case .framework: if case .framework = rhs { return true }
        case .library: if case .library = rhs { return true }
        case .other(let value): if case .other(value) = rhs { return true }
        @unknown default: break
        }
        return false
    }
}

#endif

extension String {
    static let unitTestsKind = "com.apple.product-type.bundle.unit-test"

    static let defaultSwiftlintConfigFileName = ".swiftlint.yml"
    static let testsSwiftlintConfigFileName = ".swiftlint.tests.yml"
}

extension Path {

    static let mv = Path("/bin/mv")

    /// Scans the receiver, then all of its parents looking for a configuration file with the name ".swiftlint.yml".
    ///
    /// - returns: Path to the configuration file, or nil if one cannot be found.
    func firstConfigurationFileInParentDirectories(named fileName: String = .defaultSwiftlintConfigFileName) -> Path? {
        let proposedDirectory = sequence(
            first: self,
            next: { path in
                guard path.stem.count > 1 else {
                    // Check we're not at the root of this filesystem, as `removingLastComponent()`
                    // will continually return the root from itself.
                    return nil
                }

                return path.removingLastComponent()
            }
        ).first { path in
            let potentialConfigurationFile = path.appending(subpath: fileName)
            return potentialConfigurationFile.isAccessible()
        }
        return proposedDirectory?.appending(subpath: fileName)
    }

    /// Safe way to check if the file is accessible from within the current process sandbox.
    private func isAccessible() -> Bool {
        let result = string.withCString { pointer in
            access(pointer, R_OK)
        }

        return result == 0
    }

    /// Get file modification date
    var modified: Date {
        get throws {
            try FileManager.default.attributesOfItem(atPath: self.string)[.modificationDate] as? Date ?? { throw CocoaError(.fileReadUnknown) }()
        }
    }

}
