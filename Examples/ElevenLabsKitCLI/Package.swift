// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ElevenLabsKitCLI",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
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
