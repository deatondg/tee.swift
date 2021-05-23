// swift-tools-version:5.3

import PackageDescription

let package = Package(
    name: "tee",
    products: [
        .library(name: "tee", targets: ["tee"]),
    ],
    dependencies: [],
    targets: [
        .target(name: "tee", dependencies: []),
        .testTarget(name: "teeTests", dependencies: ["tee"]),
    ]
)
