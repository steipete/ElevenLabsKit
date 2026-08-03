// swift-tools-version: 6.3

import PackageDescription

let package = Package(
    name: "ElevenLabsKitExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(name: "ElevenLabsKit", path: "../..")
    ],
    targets: [
        .executableTarget(
            name: "ElevenLabsKitExample",
            dependencies: [
                .product(name: "ElevenLabsKit", package: "ElevenLabsKit")
            ]
        )
    ]
)
