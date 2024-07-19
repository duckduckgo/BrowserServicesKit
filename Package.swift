// swift-tools-version: 5.9
// The swift-tools-version declares the minimum version of Swift required to build this package.

import Foundation
import PackageDescription

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
        .library(name: "BrowserServicesKitTestsUtils", targets: ["BrowserServicesKitTestsUtils"]),
        .library(name: "Persistence", targets: ["Persistence"]),
        .library(name: "Bookmarks", targets: ["Bookmarks"]),
        .library(name: "BloomFilterWrapper", targets: ["BloomFilterWrapper"]),
        .library(name: "UserScript", targets: ["UserScript"]),
        .library(name: "Crashes", targets: ["Crashes"]),
        .library(name: "CxxCrashHandler", targets: ["CxxCrashHandler"]),
        .library(name: "ContentBlocking", targets: ["ContentBlocking"]),
        .library(name: "PrivacyDashboard", targets: ["PrivacyDashboard"]),
        .library(name: "Configuration", targets: ["Configuration"]),
        .library(name: "Networking", targets: ["Networking"]),
        .library(name: "RemoteMessaging", targets: ["RemoteMessaging"]),
        .library(name: "RemoteMessagingTestsUtils", targets: ["RemoteMessagingTestsUtils"]),
        .library(name: "Navigation", targets: ["Navigation"]),
        .library(name: "SyncDataProviders", targets: ["SyncDataProviders"]),
        .library(name: "NetworkProtection", targets: ["NetworkProtection"]),
        .library(name: "NetworkProtectionTestUtils", targets: ["NetworkProtectionTestUtils"]),
        .library(name: "SecureStorage", targets: ["SecureStorage"]),
        .library(name: "Subscription", targets: ["Subscription"]),
        .library(name: "SubscriptionTestingUtilities", targets: ["SubscriptionTestingUtilities"]),
        .library(name: "History", targets: ["History"]),
        .library(name: "Suggestions", targets: ["Suggestions"]),
        .library(name: "PixelKit", targets: ["PixelKit"]),
        .library(name: "PixelKitTestingUtilities", targets: ["PixelKitTestingUtilities"]),
    ],
    dependencies: [
        .package(url: "https://github.com/duckduckgo/duckduckgo-autofill.git", exact: "12.0.1"),
        .package(url: "https://github.com/duckduckgo/GRDB.swift.git", exact: "2.3.0"),
        .package(url: "https://github.com/duckduckgo/TrackerRadarKit", exact: "2.1.2"),
        .package(url: "https://github.com/duckduckgo/sync_crypto", exact: "0.2.0"),
        .package(url: "https://github.com/gumob/PunycodeSwift.git", exact: "2.1.0"),
        .package(url: "https://github.com/duckduckgo/content-scope-scripts", exact: "6.3.0"),
        .package(url: "https://github.com/duckduckgo/privacy-dashboard", exact: "4.2.0"),
        .package(url: "https://github.com/httpswift/swifter.git", exact: "1.5.0"),
        .package(url: "https://github.com/duckduckgo/bloom_cpp.git", exact: "3.0.0"),
        .package(url: "https://github.com/duckduckgo/wireguard-apple", exact: "1.1.3"),
        .package(url: "https://github.com/1024jp/GzipSwift.git", exact: "6.0.1")
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
                "Subscription"
            ],
            resources: [
                .process("ContentBlocking/UserScripts/contentblockerrules.js"),
                .process("ContentBlocking/UserScripts/surrogates.js"),
                .process("SmarterEncryption/Store/HTTPSUpgrade.xcdatamodeld"),
                .copy("../../PrivacyInfo.xcprivacy")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "BrowserServicesKitTestsUtils",
            dependencies: [
                "BrowserServicesKit",
            ]
        ),
        .target(
            name: "Persistence",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
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
            ]
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
            ]
        ),
        .target(
            name: "Suggestions",
            dependencies: [
                "Common"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "BookmarksTestDBBuilder",
            dependencies: [
                "Bookmarks",
                "Persistence",
            ],
            path: "Sources/BookmarksTestDBBuilder"
        ),
        .target(
            name: "BookmarksTestsUtils",
            dependencies: [
                "Bookmarks",
            ]
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
            dependencies: [
                "Common",
                "CxxCrashHandler",
            ]),
        .target(
            name: "CxxCrashHandler",
            dependencies: ["Common"]
        ),
        .target(
            name: "DDGSync",
            dependencies: [
                "BrowserServicesKit",
                "Common",
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
                .product(name: "Gzip", package: "GzipSwift"),
                "Networking",
            ],
            resources: [
                .process("SyncMetadata.xcdatamodeld"),
                .process("SyncPDFTemplate.png")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .executableTarget(
            name: "SyncMetadataTestDBBuilder",
            dependencies: [
                "DDGSync",
                "Persistence",
            ],
            path: "Sources/SyncMetadataTestDBBuilder"
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
            ]
        ),
        .target(
            name: "ContentBlocking",
            dependencies: [
                "TrackerRadarKit",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
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
            ]
        ),
        .target(
            name: "UserScript",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
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
            ]
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
            ]
        ),
        .target(
            name: "Networking",
            dependencies: [
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "RemoteMessaging",
            dependencies: [
                "Common",
                "Configuration",
                "BrowserServicesKit",
                "Networking",
                "Persistence",
                "Subscription"
            ],
            resources: [
                .process("CoreData/RemoteMessaging.xcdatamodeld")
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "RemoteMessagingTestsUtils",
            dependencies: [
                "RemoteMessaging",
            ]
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
            ]
        ),
        .target(
            name: "TestUtils",
            dependencies: [
                "Networking",
                "Persistence",
            ]
        ),
        .target(
            name: "NetworkProtection",
            dependencies: [
                .target(name: "WireGuardC"),
                .product(name: "WireGuard", package: "wireguard-apple"),
                "Common",
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SecureStorage",
            dependencies: [
                "Common",
                .product(name: "GRDB", package: "GRDB.swift"),
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SecureStorageTestsUtils",
            dependencies: [
                "SecureStorage",
            ]
        ),
        .target(name: "WireGuardC"),
        .target(
            name: "NetworkProtectionTestUtils",
            dependencies: [
                "NetworkProtection",
            ]
        ),
        .target(
            name: "Subscription",
            dependencies: [
                "Common"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "SubscriptionTestingUtilities",
            dependencies: [
                "Subscription"
            ]
        ),
        .target(
            name: "PixelKit",
            exclude: [
                "README.md"
            ],
            swiftSettings: [
                .define("DEBUG", .when(configuration: .debug))
            ]
        ),
        .target(
            name: "PixelKitTestingUtilities",
            dependencies: [
                "PixelKit"
            ]
        ),

        // MARK: - Test Targets
        .testTarget(
            name: "HistoryTests",
            dependencies: [
                "History",
            ]
        ),
        .testTarget(
            name: "SuggestionsTests",
            dependencies: [
                "Suggestions",
            ]
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
                .copy("Resources/Bookmarks_V5.sqlite"),
                .copy("Resources/Bookmarks_V5.sqlite-shm"),
                .copy("Resources/Bookmarks_V5.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit",
                "BrowserServicesKitTestsUtils",
                "SecureStorageTestsUtils",
                "TestUtils",
                "Subscription"
            ],
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "CrashesTests",
            dependencies: [
                "Crashes"
            ]
        ),
        .testTarget(
            name: "DDGSyncTests",
            dependencies: [
                "BookmarksTestsUtils",
                "DDGSync",
                "TestUtils",
            ],
            resources: [
                .copy("Resources/SyncMetadata_V3.sqlite"),
                .copy("Resources/SyncMetadata_V3.sqlite-shm"),
                .copy("Resources/SyncMetadata_V3.sqlite-wal"),
            ]
        ),
        .testTarget(
            name: "DDGSyncCryptoTests",
            dependencies: [
                .product(name: "DDGSyncCrypto", package: "sync_crypto"),
            ]
        ),
        .testTarget(
            name: "CommonTests",
            dependencies: [
                "Common",
            ]
        ),
        .testTarget(
            name: "NetworkingTests",
            dependencies: [
                "TestUtils",
            ]
        ),
        .testTarget(
            name: "NavigationTests",
            dependencies: [
                "Navigation",
                .product(name: "Swifter", package: "swifter"),
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
            ]
        ),
        .testTarget(
            name: "UserScriptTests",
            dependencies: [
                "UserScript",
            ],
            resources: [
                .process("testUserScript.js")
            ]
        ),
        .testTarget(
            name: "PersistenceTests",
            dependencies: [
                "Persistence",
                "TrackerRadarKit",
            ]
        ),
        .testTarget(
            name: "RemoteMessagingTests",
            dependencies: [
                "BrowserServicesKitTestsUtils",
                "RemoteMessaging",
                "RemoteMessagingTestsUtils",
                "TestUtils",
            ],
            resources: [
                .copy("Resources/remote-messaging-config-example.json"),
                .copy("Resources/remote-messaging-config-malformed.json"),
                .copy("Resources/remote-messaging-config-metrics.json"),
                .copy("Resources/remote-messaging-config-unsupported-items.json"),
                .copy("Resources/remote-messaging-config.json"),
            ]
        ),
        .testTarget(
            name: "ConfigurationTests",
            dependencies: [
                "Configuration",
                "TestUtils",
            ]
        ),
        .testTarget(
            name: "SyncDataProvidersTests",
            dependencies: [
                "BookmarksTestsUtils",
                "SecureStorageTestsUtils",
                "SyncDataProviders",
            ]
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
            ]
        ),
        .testTarget(
            name: "SecureStorageTests",
            dependencies: [
                "SecureStorage",
                "SecureStorageTestsUtils",
            ]
        ),
        .testTarget(
            name: "PrivacyDashboardTests",
            dependencies: [
                "PrivacyDashboard",
                "TestUtils",
            ]
        ),
        .testTarget(
            name: "SubscriptionTests",
            dependencies: [
                "Subscription",
                "SubscriptionTestingUtilities",
            ]
        ),
        .testTarget(
            name: "PixelKitTests",
            dependencies: [
                "PixelKit",
                "PixelKitTestingUtilities",
            ]
        ),
    ],
    cxxLanguageStandard: .cxx11
)
