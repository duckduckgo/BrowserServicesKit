// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

let swiftlintPlugin = Target.PluginUsage.plugin(name: "SwiftLintPlugin", package: "apple-toolbox")

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
        .library(name: "TestUtils", targets: ["TestUtils"]),
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
        .library(name: "Subscription", targets: ["Subscription"]),
        .library(name: "History", targets: ["History"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "10.1.0"),
        .package(url: "https://github.com/duckduckgo/GRDB.swift.git", exact: "2.3.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", exact: "1.2.2"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.2.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "2.1.0"),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", exact: "3.3.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", exact: "5.4.0"),
        .package(url: "https://github.com/httpswift/swifter.git", exact: "1.5.0"),
        .package(url: "https://github.com/duckduckgo/bloom_cpp.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/wireguard-apple", exact: "1.1.1"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", exact: "2.0.0"),
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
                "SecureStorage",
                .product(name: "Macros", package: "apple-toolbox"),
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
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Bookmarks",
            dependencies: [
                "Persistence",
                "Common",
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "History",
            dependencies: [
                "Persistence",
                "Common"
            ],
            resources: [
                .process("CoreData/BrowsingHistory.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .executableTarget(
            name: "BookmarksTestDBBuilder",
            dependencies: [
                "Bookmarks",
                "Persistence",
            ],
            path: "Sources/BookmarksTestDBBuilder",
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "BookmarksTestsUtils",
            dependencies: [
                "Bookmarks",
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "BloomFilterObjC",
            dependencies: [
                .product(name: "BloomFilter", package: "bloom_cpp")
            ]),
        .target(
            name: "BloomFilterWrapper",
            dependencies: [
                "BloomFilterObjC",
            ]),
        .target(
            name: "Crashes",
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                "BrowserServicesKit",
                "Common",
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                "Networking",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            resources: [
                .process("SyncMetadata.xcdatamodeld"),
                .process("SyncPDFTemplate.png")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Common",
            dependencies: [
                .product(name: "Punnycode", package: "PunycodeSwift"),
            ],
            resources: [
                .process("TLD/tlds.json")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Navigation",
            dependencies: [
                "Common",
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
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "UserScript",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "PrivacyDashboard",
            dependencies: [
                "Common",
                "TrackerRadarKit",
                "UserScript",
                "ContentBlocking",
                "Persistence",
                "BrowserServicesKit",
                .product(name: "PrivacyDashboardResources", package: "privacy-dashboard")
            ],
            path: "Sources/PrivacyDashboard",
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Configuration",
            dependencies: [
                "Networking",
                "BrowserServicesKit",
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Networking",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "RemoteMessaging",
            dependencies: [
                "Common",
                "BrowserServicesKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "SyncDataProviders",
            dependencies: [
                "Bookmarks",
                "BrowserServicesKit",
                "Common",
                "DDGSync",
                .product(name: "GRDB", package: "GRDB.swift"),
                "Persistence",
                "SecureStorage",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "TestUtils",
            dependencies: [
                "Networking",
                "Persistence",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "NetworkProtection",
            dependencies: [
                .target(name: "WireGuardC"),
                .product(name: "WireGuard", package: "wireguard-apple"),
                "Common",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "SecureStorage",
            dependencies: [
                "Common",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "SecureStorageTestsUtils",
            dependencies: [
                "SecureStorage",
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(name: "WireGuardC"),
        .target(
            name: "NetworkProtectionTestUtils",
            dependencies: [
                "NetworkProtection",
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Subscription",
            dependencies: [
                "Common",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "HistoryTests",
            dependencies: [
                "History",
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "BookmarksTests",
            dependencies: [
                "Bookmarks",
                "BookmarksTestsUtils",
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
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit",
                "RemoteMessaging", // Move tests later (lots of test dependencies in BSK)
                "SecureStorageTestsUtils",
                "TestUtils",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            resources: [
                .copy("Resources")
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "DDGSyncTests",
            dependencies: [
                "DDGSync",
                "TestUtils",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "TestUtils",
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NavigationTests",
            dependencies: [
                "Navigation",
                .product(name: "Swifter", package: "swifter"),
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("_NAVIGATION_REQUEST_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "UserScript",
            ],
            resources: [
                .process("testUserScript.js")
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "TrackerRadarKit",
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "Configuration",
                "TestUtils",
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "SyncDataProvidersTests",
            dependencies: [
                "BookmarksTestsUtils",
                "SecureStorageTestsUtils",
                "SyncDataProviders",
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NetworkProtectionTests",
            dependencies: [
                "NetworkProtection",
                "NetworkProtectionTestUtils",
            ],
            resources: [
                .copy("Resources/servers-original-endpoint.json"),
                .copy("Resources/servers-updated-endpoint.json"),
                .copy("Resources/locations-endpoint.json")
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "SecureStorageTests",
            dependencies: [
                "SecureStorage",
                "SecureStorageTestsUtils",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "PrivacyDashboardTests",
            dependencies: [
                "PrivacyDashboard",
                "TestUtils",
                .product(name: "Macros", package: "apple-toolbox"),
            ],
            plugins: [swiftlintPlugin]
        ),
    ],
    cxxLanguageStandard: .cxx11
)

// validate all targets have swiftlint plugin
for target in package.targets {
    let targetsWithSwiftlintDisabled: Set<String> = [
        "BloomFilterObjC",
        "BloomFilterWrapper",
        "WireGuardC",
    ]
    guard !targetsWithSwiftlintDisabled.contains(target.name) else { continue }
    guard target.plugins?.contains(where: {
        "\($0)" == "\(Target.PluginUsage.plugin(name: "SwiftLintPlugin", package: "apple-toolbox"))"
    }) == true else {
        assertionFailure("""

        Target \(target.name) is missing SwiftLintPlugin dependency.
        If this is intended, add \"\(target.name)\" to targetsWithSwiftlintDisabled
        Target plugins: \(target.plugins?.map { "\($0)" }.joined(separator: ", ") ?? "<nil>")
        """)
        continue
    }
}
