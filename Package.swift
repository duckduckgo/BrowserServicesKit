// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15")
    ],
    products: [
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "Common", targets: ["Common"])
    ],
    dependencies: [
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("5.2.0")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.2.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.1.1")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0")),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", .exact("3.1.0"))
    ],
    targets: [
        
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "Autofill",
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "GRDB",
                "TrackerRadarKit",
                .product(name: "Punnycode", package: "Punycode"),
                "BloomFilterWrapper"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .process("TLD/tlds.json")
            ]),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilter"
            ]),
        .target(
            name: "BloomFilter",
            resources: [
                .process("CMakeLists.txt")
            ]),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punnycode", package: "Punycode")
            ]),
        
        // MARK: - Test targets
        
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit"
            ],
            resources: [
                .process("UserScript/testUserScript.js"),
                .copy("Resources")
            ]),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common"
            ]
        )
    ]
)
