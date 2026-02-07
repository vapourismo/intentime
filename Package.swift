// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "Intentime",
    platforms: [.macOS(.v14)],
    targets: [
        .executableTarget(
            name: "Intentime",
            path: "Sources/Intentime"
        ),
    ]
)
