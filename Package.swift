// swift-tools-version: 5.9
import PackageDescription

let package = Package(
    name: "TerrainGenerationKit",
    platforms: [
        .iOS(.v15),
        .macOS(.v12)
    ],
    products: [
        .library(
            name: "TerrainGenerationKit",
            targets: ["TerrainGenerationKit"]
        )
    ],
    targets: [
        .target(
            name: "TerrainGenerationKit",
            resources: [
                .process("Compute/Resources")
            ]
        ),
        .testTarget(
            name: "TerrainGenerationKitTests",
            dependencies: ["TerrainGenerationKit"]
        )
    ]
)
