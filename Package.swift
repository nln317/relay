// swift-tools-version: 6.0
// RelayKit: the platform-independent core of Relay (working codename).
// Everything in here except RelayUI builds and tests on Linux, so the rules
// engine, wire protocol and draft/recovery logic are verified without Xcode.
import PackageDescription

let package = Package(
    name: "RelayKit",
    platforms: [.iOS(.v17), .macOS(.v14)],
    products: [
        .library(name: "RelayCore", targets: ["RelayCore"]),
        .library(name: "RelayGames", targets: ["RelayGames"]),
        .library(name: "RelayMessages", targets: ["RelayMessages"]),
        .library(name: "RelayAnalytics", targets: ["RelayAnalytics"]),
        .library(name: "RelayUI", targets: ["RelayUI"]),
    ],
    targets: [
        .target(name: "RelayCore"),
        .target(name: "RelayGames", dependencies: ["RelayCore"]),
        .target(name: "RelayAnalytics", dependencies: ["RelayCore"]),
        .target(name: "RelayMessages", dependencies: ["RelayCore", "RelayGames", "RelayAnalytics"]),
        // SwiftUI views. Every file is wrapped in `#if canImport(UIKit)`, so on
        // Linux this target compiles to an empty module.
        .target(name: "RelayUI", dependencies: ["RelayCore", "RelayGames", "RelayMessages", "RelayAnalytics"]),
        .testTarget(name: "RelayCoreTests", dependencies: ["RelayCore"]),
        .testTarget(name: "RelayGamesTests", dependencies: ["RelayCore", "RelayGames"]),
        .testTarget(name: "RelayMessagesTests", dependencies: ["RelayCore", "RelayGames", "RelayMessages", "RelayAnalytics"]),
    ],
    swiftLanguageModes: [.v6]
)
