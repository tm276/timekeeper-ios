// swift-tools-version: 6.0

import PackageDescription

let package = Package(
    name: "timekeeper",
    platforms: [
        .iOS(.v17),
        .macOS(.v14),
    ],
    products: [
        .library(
            name: "timekeeper",
            targets: ["timekeeper"]
        ),
    ],
    targets: [
        .target(
            name: "timekeeper"
        ),
    ]
)
