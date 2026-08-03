// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ElevenLabsKitCLI",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "ElevenLabsKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ElevenLabsKitCLI",
            dependencies: [
                .product(name: "ElevenLabsKit", package: "ElevenLabsKit")
            ]
        )
    ]
)
