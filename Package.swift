// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "ElevenLabsKit",
    platforms: [
        .iOS(.v17),
        .macOS(.v15),
    ],
    products: [
        .library(name: "ElevenLabsKit", targets: ["ElevenLabsKit"]),
    ],
    targets: [
        .target(
            name: "ElevenLabsKit",
            dependencies: []),
        .testTarget(
            name: "ElevenLabsKitTests",
            dependencies: ["ElevenLabsKit"],
            swiftSettings: [
                .enableExperimentalFeature("SwiftTesting"),
            ]),
    ])
