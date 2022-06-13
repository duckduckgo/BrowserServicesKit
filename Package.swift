// swift-tools-version:5.5
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS(.v13),
        .macOS(.v10_15)
    ],
    products: [
        // 3rd Party Submodules
        .library(name: "Clibsodium", targets: ["Clibsodium"]),

        // Intermediate dependencies
        .library(name: "DDGSyncCrypto", targets: ["DDGSyncCrypto"]),

        // Exported libraries
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "DDGSync", targets: ["DDGSync"]),

        .executable(name: "ddgsynccli", targets: ["DDGSyncCLI"])
    ],
    dependencies: [
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("4.6.0")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.1.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.0.4")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0"))
    ],
    targets: [
        
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "Autofill",
                "GRDB",
                "TrackerRadarKit",
                .product(name: "Punnycode", package: "Punycode"),
                "BloomFilterWrapper"
            ],
            exclude: [
                "Resources/content-scope-scripts/README.md",
                "Resources/content-scope-scripts/package-lock.json",
                "Resources/content-scope-scripts/package.json",
                "Resources/content-scope-scripts/LICENSE.md",
                "Resources/content-scope-scripts/src/",
                "Resources/content-scope-scripts/unit-test/",
                "Resources/content-scope-scripts/integration-test/",
                "Resources/content-scope-scripts/scripts/",
                "Resources/content-scope-scripts/inject/",
                "Resources/content-scope-scripts/lib/",
                "Resources/content-scope-scripts/build/chrome/",
                "Resources/content-scope-scripts/build/firefox/",
                "Resources/content-scope-scripts/build/integration/"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .process("Resources/content-scope-scripts/build/apple/contentScope.js")
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
        .binaryTarget(
                name: "Clibsodium",
                path: "Clibsodium.xcframework"),
        .target(
            name: "DDGSyncCrypto",
            dependencies: [
                "Clibsodium"
            ]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                "BrowserServicesKit",
                "DDGSyncCrypto"
            ]
        ),

        // Command line app targets
        .executableTarget(
            name: "DDGSyncCLI",
            dependencies: [
                "DDGSync"
            ]
        ),

        // Test Targets
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
            name: "DDGSyncTests",
            dependencies: [
                "DDGSync"
            ]),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                "DDGSyncCrypto"
            ])
    ]
)
