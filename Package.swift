// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("14.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Common", targets: ["Common"]),
        .library(name: "Crashes", targets: ["Crashes"])
    ],
    dependencies: [
        .package(name: "BloomFilter", url: "https://github.com/duckduckgo/bloom_cpp.git", .revision("14b66a24a6c185d949e78b86b3ea51ad5c7cb51f")),
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("5.3.1")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.2.1")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.1.1")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0")),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", .exact("3.2.0"))
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "Autofill",
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "GRDB",
                "TrackerRadarKit",
                "BloomFilterWrapper",
                "UserScript",
                "Common"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilter"
            ]),
        .target(
            name: "UserScript"
        ),
        .target(
            name: "Crashes"
        ),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punnycode", package: "Punycode")
            ],
            resources: [
                .process("TLD/tlds.json")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]),
        
        // MARK: - Test targets
        
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit"
            ],
            resources: [
                .copy("Resources")
            ]),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common"
            ]),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "UserScript"
            ],
            resources: [
                .process("testUserScript.js")
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
