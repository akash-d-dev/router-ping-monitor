// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "PingPong",
    platforms: [.macOS(.v14)],
    products: [
        .executable(name: "PingPong", targets: ["PingPong"])
    ],
    targets: [
        .executableTarget(
            name: "PingPong",
            path: "Sources/PingPong"
        )
    ]
)
