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
        .library(name: "PrivacyDashboardCode", targets: ["PrivacyDashboardCode"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Common", targets: ["Common"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"])
    ],
    dependencies: [
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("5.0.1")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("1.2.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.1.1")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0")),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", .exact("2.4.1"))
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
                "Common",
                "ContentBlocking"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js")
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
                "BrowserServicesKit",
                "Common",
                "UserScript",
                "PrivacyDashboardCode"
            ],
            resources: [
                .process("UserScript/testUserScript.js"),
                .copy("Resources")
            ]),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punnycode", package: "Punycode")
            ],
            resources: [
                .process("TLD/tlds.json")
            ]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit"
            ]
        ),
        .target(
            name: "UserScript"
        ),
        .target(
            name: "PrivacyDashboardCode",
            dependencies: [
                "Common",
                "TrackerRadarKit",
                "UserScript",
                "ContentBlocking"
            ],
            path: "Sources/PrivacyDashboard"
            )
        
    ]
)
