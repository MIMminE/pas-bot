// swift-tools-version: 5.9

import PackageDescription

let package = Package(
    name: "PASMenuBar",
    platforms: [
        .macOS(.v13)
    ],
    products: [
        .executable(name: "PASMenuBar", targets: ["PASMenuBar"])
    ],
    targets: [
        .executableTarget(
            name: "PASMenuBar",
            path: "Sources"
        )
    ]
)
