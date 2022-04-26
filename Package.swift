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
        .library(name: "DDGSyncAuth", targets: ["DDGSyncAuth"]),

        // Exported libraries
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "DDGSync", targets: ["DDGSync"]),

        .executable(name: "ddgsynccli", targets: ["DDGSyncCLI"])
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.1.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.0.3")),
    ],
    targets: [
        
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "GRDB",
                "TrackerRadarKit",
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
                "Resources/content-scope-scripts/build/integration/",
                "Resources/duckduckgo-autofill/Gruntfile.js",
                "Resources/duckduckgo-autofill/package.json",
                "Resources/duckduckgo-autofill/package-lock.json",
                "Resources/duckduckgo-autofill/packages/",
                "Resources/duckduckgo-autofill/integration-test/",
                "Resources/duckduckgo-autofill/LICENSE.md",
                "Resources/duckduckgo-autofill/README.md",
                "Resources/duckduckgo-autofill/src",
                "Resources/duckduckgo-autofill/dist/autofill-host-styles_firefox.css",
                "Resources/duckduckgo-autofill/dist/autofill.css",
                "Resources/duckduckgo-autofill/jest.setup.js",
                "Resources/duckduckgo-autofill/dist/autofill-host-styles_chrome.css",
                "Resources/duckduckgo-autofill/jest.config.js",
                "Resources/duckduckgo-autofill/jest-test-environment.js",
                "Resources/duckduckgo-autofill/scripts/",
                "Resources/duckduckgo-autofill/jesthtmlreporter.config.json",
                "Resources/duckduckgo-autofill/types.d.ts",
                "Resources/duckduckgo-autofill/tsconfig.json",
                "Resources/duckduckgo-autofill/docs/real-world-html-tests.md",
                "Resources/duckduckgo-autofill/docs/matcher-configuration.md"
            ],
            resources: [
                .process("Resources/duckduckgo-autofill/dist/autofill.js"),
                .process("Resources/duckduckgo-autofill/dist/TopAutofill.html"),
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
            name: "DDGSyncAuth",
            dependencies: [
                "Clibsodium"
            ]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                "BrowserServicesKit",
                "DDGSyncAuth"
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
            name: "DDGSyncAuthTests",
            dependencies: [
                "DDGSyncAuth"
            ])
    ]
)
