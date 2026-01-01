// swift-tools-version: 6.2

import PackageDescription

let package = Package(
    name: "ElevenLabsKitExample",
    platforms: [
        .macOS(.v15)
    ],
    dependencies: [
        .package(path: "../..")
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
