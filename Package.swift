// swift-tools-version:5.3
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

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
        .package(name: "GRDB", url: "git@github.com:duckduckgo/GRDB.swift.git", .branch("SQLCipher")),
    ],
    targets: [
        .target(
            name: "BrowserServicesKit",
            dependencies: [
                "GRDB",
            ],
            resources: [
                .process("Email/email-autofill.css"),
                .process("Email/email-autofill.js")
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
