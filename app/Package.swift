// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "Duet",
    platforms: [
        .macOS(.v14)
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
