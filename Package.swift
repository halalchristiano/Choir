// swift-tools-version: 6.3
import PackageDescription

let package = Package(
    name: "Choir",
    // PKG-003 sets the minimum deployment targets. They were previously one
    // major version low on iOS, macOS and watchOS.
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
        .visionOS(.v1),
        .watchOS(.v10),
        .tvOS(.v17),
    ],
    products: [
        .library(
            name: "Choir",
            targets: ["Choir"]
        ),
        // PRF-040 requires the benchmark harness to be part of the repository
        // and runnable per release on each reference device.
        .executable(
            name: "choir-benchmark",
            targets: ["ChoirBenchmark"]
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
                .copy("Resources/cmudict.lex"),
                .copy("Resources/CMUDICT-LICENSE.txt"),
            ],
            swiftSettings: [
                .swiftLanguageMode(.v6)
            ]
        ),
        .executableTarget(
            name: "ChoirBenchmark",
            dependencies: ["Choir"],
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
