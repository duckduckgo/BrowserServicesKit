// swift-tools-version:5.7
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let swiftlintPlugin = Target.PluginUsage.plugin(name: "SwiftLintPlugin", package: "AppleToolbox")
let swiftlintDependency = Target.Dependency.product(name: "SwiftLintPlugin", package: "apple-toolbox")

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
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "10.1.0"),
        .package(url: "https://github.com/duckduckgo/GRDB.swift.git", exact: "2.3.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", exact: "1.2.2"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.2.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "2.1.0"),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", exact: "3.2.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", exact: "4.64.0"),
        .package(url: "https://github.com/httpswift/swifter.git", exact: "1.5.0"),
        .package(url: "https://github.com/duckduckgo/bloom_cpp.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/wireguard-apple", exact: "1.1.1"),
        .package(url: "https://github.com/duckduckgo/apple-toolbox.git", revision: "449a81d5f31af91033c0a7c47f8ca2b0c9362aea"),
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            resources: [
                .process("BookmarksModel.xcdatamodeld")
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
                swiftlintDependency,
            ],
            path: "Sources/BookmarksTestDBBuilder",
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "BookmarksTestsUtils",
            dependencies: [
                "Bookmarks",
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                .product(name: "PrivacyDashboardResources", package: "privacy-dashboard"),
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "NetworkProtection",
            dependencies: [
                .target(name: "WireGuardC"),
                .product(name: "WireGuard", package: "wireguard-apple"),
                "Common",
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(name: "WireGuardC"),
        .target(
            name: "NetworkProtectionTestUtils",
            dependencies: [
                "NetworkProtection",
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .target(
            name: "Subscription",
            dependencies: [
                "Common",
                swiftlintDependency,
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ],
            plugins: [swiftlintPlugin]
        ),

        // MARK: - Test Targets

        .testTarget(
            name: "BookmarksTests",
            dependencies: [
                "Bookmarks",
                "BookmarksTestsUtils",
                swiftlintDependency,
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
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "TestUtils",
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NavigationTests",
            dependencies: [
                "Navigation",
                .product(name: "Swifter", package: "swifter"),
                swiftlintDependency,
            ],
            resources: [
                .copy("Resources")
            ],
            swiftSettings: [
                .define("_IS_USER_INITIATED_ENABLED", .when(platforms: [.macOS])),
                .define("_FRAME_HANDLE_ENABLED", .when(platforms: [.macOS])),
                .define("PRIVATE_NAVIGATION_DID_FINISH_CALLBACKS_ENABLED", .when(platforms: [.macOS])),
                .define("_WEBPAGE_PREFS_CUSTOM_HEADERS_ENABLED", .when(platforms: [.macOS])),
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "UserScript",
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "Configuration",
                "TestUtils",
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "SyncDataProvidersTests",
            dependencies: [
                "BookmarksTestsUtils",
                "SecureStorageTestsUtils",
                "SyncDataProviders",
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "NetworkProtectionTests",
            dependencies: [
                "NetworkProtection",
                "NetworkProtectionTestUtils",
                swiftlintDependency,
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
                swiftlintDependency,
            ],
            plugins: [swiftlintPlugin]
        ),
        .testTarget(
            name: "PrivacyDashboardTests",
            dependencies: [
                "PrivacyDashboard",
                "TestUtils",
                swiftlintDependency,
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
    guard target.plugins?.contains(where: { "\($0)" == "\(Target.PluginUsage.plugin(name: "SwiftLintPlugin", package: "AppleToolbox"))" }) == true else {
        assertionFailure("\nTarget \(target.name) is missing SwiftLintPlugin dependency.\nIf this is intended, add \"\(target.name)\" to targetsWithSwiftlintDisabled\nTarget plugins: "
                         + (target.plugins?.map { "\($0)" }.joined(separator: ", ") ?? "<nil>"))
        continue
    }
}
