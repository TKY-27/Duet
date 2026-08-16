// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Duet",
    platforms: [
        // macOS 26 only. The redesign builds on the current design language and
        // toolbar/inspector APIs; supporting older releases would mean shipping
        // a second, untested visual path.
        .macOS(.v26)
    ],
    products: [
        .executable(name: "Duet", targets: ["Duet"])
    ],
    targets: [
        .executableTarget(
            name: "Duet",
            path: "Sources/Duet",
            resources: [
                .copy("Resources")
            ]
        ),
        .testTarget(
            name: "DuetTests",
            dependencies: ["Duet"],
            path: "Tests/DuetTests"
        )
    ]
)
