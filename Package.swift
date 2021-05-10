// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription
import Foundation

let package = Package(
    name: "BrowserServicesKit",
    platforms: [
        .iOS("13.0"),
        .macOS("10.15"),
    ],
    products: [
        .library(name: "BrowserServicesKit", targets: ["BrowserServicesKit"]),
        .library(name: "SecureVault", targets: ["SecureVault"]),
    ],
    dependencies: [
        .package(name: "GRDB", url: "https://github.com/duckduckgo/GRDB.swift.git", .revision("e5714d4b6ee1651d2271b04ae85aaf5a327fe70a")),
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [],
            // ideally exclude `Resources/duckduckgo-autofill` explicitly, but doing so prevents Bundle.module being generated
            resources: [
                .process("Resources/duckduckgo-autofill/dist/autofill.js")
            ]),
        .target(
            name: "SecureVault",
            dependencies: [
                "BrowserServicesKit",
                "GRDB",
            ]),
        .testTarget(
            name: "BrowserServicesKitTests",
            dependencies: [
                "BrowserServicesKit",
                "SecureVault"
            ],
            resources: [
                .copy("UserScript/testUserScript.js")
            ])
    ]
)
