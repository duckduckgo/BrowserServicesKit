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
        .library(name: "Common", targets: ["Common"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Crashes", targets: ["Crashes"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "PrivacyDashboard", targets: ["PrivacyDashboard"])
    ],
    dependencies: [
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("6.2.0")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("2.0.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.1.1")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0")),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", .exact("3.4.1")),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", .exact("1.4.0"))
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "Autofill",
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "Persistence",
                "GRDB",
                "TrackerRadarKit",
                "BloomFilterWrapper",
                "Common",
                "UserScript",
                "ContentBlocking"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]),
        .target(
            name: "Persistence",
            dependencies: [
                "Common"
            ]
        ),
        .target(
            name: "Bookmarks",
            dependencies: [
                "Persistence",
                "Common"
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
            ]
        ),
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
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit"
            ]),
        .target(
            name: "UserScript"
            ),
        .target(
            name: "PrivacyDashboard",
            dependencies: [
                "Common",
                "TrackerRadarKit",
                "UserScript",
                "ContentBlocking",
                .product(name: "PrivacyDashboardResources", package: "privacy-dashboard")
            ],
            path: "Sources/PrivacyDashboard"
            ),
        
        // MARK: - Test targets
        
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
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
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence"
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
