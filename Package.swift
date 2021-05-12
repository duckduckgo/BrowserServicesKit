// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "SecureVault", targets: ["SecureVault"]),
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .revision("e5714d4b6ee1651d2271b04ae85aaf5a327fe70a")),
    ],
    targets: [
        Target.target(
            name: "BrowserServicesKit",
            dependencies: [],
            resources: [
                .process("Resources/duckduckgo-autofill/dist/autofill.js")
            ]).excluding(filesRecursingDirectoryAt: "Resources/duckduckgo-autofill/",
                         except: ["dist/autofill.js"]),
        .target(
            name: "SecureVault",
            dependencies: [
                "BrowserServicesKit",
                "GRDB",
            ]),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit",
                "SecureVault"
            ],
            resources: [
                .copy("UserScript/testUserScript.js")
            ])
    ]
)

extension Target {

    func excluding(filesRecursingDirectoryAt exclusionPath: String,
                   except exceptions: [String]) -> Target {
        assert(sources == nil, "Custom sources location not supported.")

        func allFiles(recursingDirectory dir: URL) -> [URL] {
            let fm = FileManager.default
            let files = (try? fm.contentsOfDirectory(at: dir,
                                                     includingPropertiesForKeys: nil,
                                                     options: [ .skipsHiddenFiles ])) ?? []
            return files.map {
                $0.hasDirectoryPath ? allFiles(recursingDirectory: $0) : [$0]
            }.flatMap {
                $0
            }
        }

        var sourcesPath = URL(fileURLWithPath: #file)
        sourcesPath.deleteLastPathComponent()
        sourcesPath.appendPathComponent("Sources")
        sourcesPath.appendPathComponent(name)

        let exclusionPath = sourcesPath.appendingPathComponent(exclusionPath)
        let exceptionUrls = exceptions.map {
            URL(fileURLWithPath: $0, relativeTo: exclusionPath)
        }

        let exclusions = allFiles(recursingDirectory: exclusionPath).filter({
            !exceptionUrls.contains($0)
        }).map {
            String($0.path.dropFirst(sourcesPath.path.count + 1))
        }

        return .target(name: name,
                       dependencies: dependencies,
                       path: path,
                       exclude: exclude + exclusions,
                       sources: sources,
                       resources: resources,
                       publicHeadersPath: publicHeadersPath,
                       cSettings: cSettings,
                       cxxSettings: cxxSettings,
                       swiftSettings: swiftSettings,
                       linkerSettings: linkerSettings)
    }

}
