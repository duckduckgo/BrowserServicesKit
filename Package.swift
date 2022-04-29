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
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"])
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.1.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .branch("brad/cname-load-types")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0"))
    ],
    targets: [
        
        .target(
            name: "BrowserServicesKit",
            dependencies: [
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
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit"
            ],
            resources: [
                .process("UserScript/testUserScript.js"),
                .copy("Resources")
            ])
    ]
)
