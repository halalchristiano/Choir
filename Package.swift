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
            resources: [
                // Built-in pronunciation lexicon (SRS TXT-020). CMUdict,
                // redistributed under its BSD-2-Clause licence; see
                // Sources/Choir/Resources/CMUDICT-LICENSE.txt.
                .copy("Resources/cmudict.dict"),
                .copy("Resources/CMUDICT-LICENSE.txt"),
            ],
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
