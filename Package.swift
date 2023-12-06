// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("14.0"),
        .macOS("11.4")
    ],
    products: [
        // Exported libraries
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "Common", targets: ["Common"]),
        .library(name: "DDGSync", targets: ["DDGSync"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "BloomFilterWrapper", targets: ["BloomFilterWrapper"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Crashes", targets: ["Crashes"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "PrivacyDashboard", targets: ["PrivacyDashboard"]),
        .library(name: "Configuration", targets: ["Configuration"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "RemoteMessaging", targets: ["RemoteMessaging"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "SyncDataProviders", targets: ["SyncDataProviders"]),
        .library(name: "NetworkProtection", targets: ["NetworkProtection"]),
        .library(name: "NetworkProtectionTestUtils", targets: ["NetworkProtectionTestUtils"]),
        .library(name: "SecureStorage", targets: ["SecureStorage"]),
        .plugin(name: "SwiftLintPlugin", targets: ["SwiftLintPlugin"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "10.0.0"),
        .package(url: "https://github.com/duckduckgo/GRDB.swift.git", exact: "2.2.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", exact: "1.2.1"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.2.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "2.1.0"),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", exact: "3.1.1" ),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", exact: "4.52.0"),
        .package(url: "https://github.com/httpswift/swifter.git", exact: "1.5.0"),
        .package(url: "https://github.com/duckduckgo/bloom_cpp.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/wireguard-apple", exact: "1.1.1"),
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                .product(name: "Autofill", package: "duckduckgo-autofill"),
                .product(name: "ContentScopeScripts", package: "content-scope-scripts"),
                "Persistence",
                "TrackerRadarKit",
                "BloomFilterWrapper",
                "Common",
                "UserScript",
                "ContentBlocking",
                "SecureStorage"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .process("SmarterEncryption/Store/HTTPSUpgrade.xcdatamodeld"),
                .copy("../../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Common"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "Bookmarks",
            dependencies: [
                "Persistence",
                "Common"
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .executableTarget(
            name: "BookmarksTestDBBuilder",
            dependencies: [
                "Bookmarks",
                "Persistence"
            ],
            path: "Sources/BookmarksTestDBBuilder",
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "BookmarksTestsUtils",
            dependencies: [
                "Bookmarks"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "BloomFilterObjC",
            dependencies: [
                .product(name: "BloomFilter", package: "bloom_cpp")
            ]),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilterObjC"
            ]),
        .target(
            name: "Crashes",
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                "Common",
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                "Networking"
            ],
            resources: [
                .process("SyncMetadata.xcdatamodeld"),
                .process("SyncPDFTemplate.png")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punnycode", package: "PunycodeSwift")
            ],
            resources: [
                .process("TLD/tlds.json")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
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
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "UserScript",
            dependencies: [
                "Common"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
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
            path: "Sources/PrivacyDashboard",
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "Configuration",
            dependencies: [
                "Networking",
                "BrowserServicesKit",
                "Common"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "Networking",
            dependencies: [
                "Common"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "RemoteMessaging",
            dependencies: [
                "Common",
                "BrowserServicesKit"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "SyncDataProviders",
            dependencies: [
                "Bookmarks",
                "BrowserServicesKit",
                "DDGSync",
                .product(name: "GRDB", package: "GRDB.swift"),
                "Persistence",
                "SecureStorage"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "TestUtils",
            dependencies: [
                "Networking"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "NetworkProtection",
            dependencies: [
                .target(name: "WireGuardC"),
                .product(name: "WireGuard", package: "wireguard-apple"),
                "Common"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "SecureStorage",
            dependencies: [
                "Common",
                .product(name: "GRDB", package: "GRDB.swift")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(
            name: "SecureStorageTestsUtils",
            dependencies: [
                "SecureStorage"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .target(name: "WireGuardC"),
        .target(
            name: "NetworkProtectionTestUtils",
            dependencies: [
                "NetworkProtection"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "BookmarksTests",
            dependencies: [
                "Bookmarks",
                "BookmarksTestsUtils"
            ],
            resources: [
                .copy("Resources/Bookmarks_V1.sqlite"),
                .copy("Resources/Bookmarks_V1.sqlite-shm"),
                .copy("Resources/Bookmarks_V1.sqlite-wal"),
                .copy("Resources/Bookmarks_V2.sqlite"),
                .copy("Resources/Bookmarks_V2.sqlite-shm"),
                .copy("Resources/Bookmarks_V2.sqlite-wal"),
                .copy("Resources/Bookmarks_V3.sqlite"),
                .copy("Resources/Bookmarks_V3.sqlite-shm"),
                .copy("Resources/Bookmarks_V3.sqlite-wal"),
                .copy("Resources/Bookmarks_V4.sqlite"),
                .copy("Resources/Bookmarks_V4.sqlite-shm"),
                .copy("Resources/Bookmarks_V4.sqlite-wal"),
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit",
                "RemoteMessaging", // Move tests later (lots of test dependencies in BSK)
                "SecureStorageTestsUtils"
            ],
            resources: [
                .copy("Resources")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "DDGSyncTests",
            dependencies: [
                "DDGSync"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                .product(name: "DDGSyncCrypto", package: "sync_crypto")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "TestUtils"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
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
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "UserScript"
            ],
            resources: [
                .process("testUserScript.js")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "TrackerRadarKit"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "Configuration",
                "TestUtils"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "SyncDataProvidersTests",
            dependencies: [
                "BookmarksTestsUtils",
                "SecureStorageTestsUtils",
                "SyncDataProviders"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .plugin(
            name: "SwiftLintPlugin",
            capability: .buildTool(),
            dependencies: [
                .target(name: "SwiftLintBinary", condition: .when(platforms: [.macOS]))
            ]
        ),
        .binaryTarget(
            name: "SwiftLintBinary",
            url: "https://github.com/realm/SwiftLint/releases/download/0.54.0/SwiftLintBinary-macos.artifactbundle.zip",
            checksum: "963121d6babf2bf5fd66a21ac9297e86d855cbc9d28322790646b88dceca00f1"
        ),
        .testTarget(
            name: "NetworkProtectionTests",
            dependencies: [
                "NetworkProtection",
                "NetworkProtectionTestUtils"
            ],
            resources: [
                .copy("Resources/servers-original-endpoint.json"),
                .copy("Resources/servers-updated-endpoint.json"),
                .copy("Resources/locations-endpoint.json")
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
        .testTarget(
            name: "SecureStorageTests",
            dependencies: [
                "SecureStorage",
                "SecureStorageTestsUtils"
            ],
            plugins: [.plugin(name: "SwiftLintPlugin")]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
