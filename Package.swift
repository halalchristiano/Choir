// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Choir",
    platforms: [
        .iOS(.v16),
        .macOS(.v13),
        .visionOS(.v1),
        .watchOS(.v9),
        .tvOS(.v16),
    ],
    products: [
        .library(
            name: "Choir",
            targets: ["Choir"]
        ),
    ],
    targets: [
        .target(
            name: "Choir",
            dependencies: [],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .testTarget(
            name: "ChoirTests",
            dependencies: ["Choir"]
        ),
    ]
)
