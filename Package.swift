// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "AIUsageKit",
    defaultLocalization: "en",
    platforms: [
        .iOS("26.0"),
        .macOS("26.0"),
        .watchOS("26.0"),
        .visionOS("26.0"),
    ],
    products: [
        // Everything an app or extension draws usage with: sign-ins, fetching, the shared cache,
        // the views, the widget, and the Mac's menu bar extra.
        .library(name: "AIUsageKit", targets: ["AIUsageKit"]),
        // The "Get AI Usage" App Intent. Its own product so only the app links it — an extension
        // that registered it too would offer the action twice.
        .library(name: "AIUsageKitIntents", targets: ["AIUsageKitIntents"]),
    ],
    dependencies: [
        .package(url: "https://github.com/kishikawakatsumi/KeychainAccess.git", from: "4.2.2"),
    ],
    targets: [
        .target(
            name: "AIUsageKit",
            dependencies: ["KeychainAccess"],
            resources: [.process("Resources")],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .target(
            name: "AIUsageKitIntents",
            dependencies: ["AIUsageKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
        .testTarget(
            name: "AIUsageKitTests",
            dependencies: ["AIUsageKit"],
            swiftSettings: [.swiftLanguageMode(.v5)]),
    ]
)
