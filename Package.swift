// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
    name: "CaptureCLI",
    products: [
        .library(
            name: "CaptureCLI",
            targets: ["CaptureCLI"]),
    ],
    targets: [
        .target(
            name: "CaptureCLI",
            dependencies: []),
        .testTarget(
            name: "CaptureCLITests",
            dependencies: ["CaptureCLI"]),
    ]
)
