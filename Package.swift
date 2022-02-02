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
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.1.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.0.3"))
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "GRDB",
                "TrackerRadarKit"
            ],
            exclude: [
                "Resources/duckduckgo-autofill/Gruntfile.js",
                "Resources/duckduckgo-autofill/package.json",
                "Resources/duckduckgo-autofill/package-lock.json",
                "Resources/duckduckgo-autofill/LICENSE.md",
                "Resources/duckduckgo-autofill/README.md",
                "Resources/duckduckgo-autofill/src",
                "Resources/duckduckgo-autofill/dist/autofill-host-styles_firefox.css",
                "Resources/duckduckgo-autofill/dist/autofill.css",
                "Resources/duckduckgo-autofill/jest.setup.js",
                "Resources/duckduckgo-autofill/dist/autofill-host-styles_chrome.css",
                "Resources/duckduckgo-autofill/jest.config.js",
                "Resources/duckduckgo-autofill/jest-test-environment.js"
            ],
            resources: [
                .process("Resources/duckduckgo-autofill/dist/autofill.js"),
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js")
            ]),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit"
            ],
            resources: [
                .process("UserScript/testUserScript.js"),
                .process("Resources")
            ])
    ]
)
