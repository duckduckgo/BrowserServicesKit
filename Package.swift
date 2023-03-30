// swift-tools-version:5.5
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
        // Exported libraries
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "Common", targets: ["Common"]),
        .library(name: "DDGSync", targets: ["DDGSync"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Crashes", targets: ["Crashes"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "PrivacyDashboard", targets: ["PrivacyDashboard"]),
        .library(name: "Configuration", targets: ["Configuration"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "Navigation", targets: ["Navigation"]),
    ],
    dependencies: [
        .package(name: "Autofill", url: "https://github.com/duckduckgo/duckduckgo-autofill.git", .exact("6.4.1")),
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .exact("2.0.0")),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", .exact("1.2.1")),
        .package(url: "https://github.com/duckduckgo/sync_crypto", .exact("0.2.0")),
        .package(name: "Punycode", url: "https://github.com/gumob/PunycodeSwift.git", .exact("2.1.0")),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", .exact("4.4.4")),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", .exact("1.4.0")),
        .package(url: "https://github.com/httpswift/swifter.git", .exact("1.5.0")),
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
            name: "DDGSync",
            dependencies: [
                "Common",
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                "Networking"
            ]
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
            ]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit"
            ]),
        .target(
            name: "Navigation",
            dependencies: [
                "Common"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug)),
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("WILLPERFORMCLIENTREDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_IS_REDIRECT_ENABLED", .when(platforms: [.macOS])),
                .define("_MAIN_FRAME_NAVIGATION_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("TERMINATE_WITH_REASON_ENABLED", .when(platforms: [.macOS])),
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
        .target(
            name: "Configuration",
            dependencies: [
                "Networking",
                "BrowserServicesKit",
                "Common"
            ]),
        .target(
            name: "Networking",
            dependencies: [
                "Common"
            ]),
        .target(
            name: "TestUtils",
            dependencies: [
                "Networking"
            ]),
        
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
            name: "DDGSyncTests",
            dependencies: [
                "DDGSync"
            ]),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                .product(name: "DDGSyncCrypto", package: "sync_crypto")
            ]),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common"
            ]),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "TestUtils"
            ]),
        .testTarget(
            name: "NavigationTests",
            dependencies: [
                "Navigation",
                .product(name: "Swifter", package: "swifter")
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
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
                "Persistence",
                "TrackerRadarKit"
            ]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "Configuration",
                "TestUtils"
            ]
        )
    ],
    cxxLanguageStandard: .cxx11
)
