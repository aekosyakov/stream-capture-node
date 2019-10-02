// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "CaptureCLI",
  platforms: [
    .macOS(.v10_13)
  ],
  products: [
    .executable(
      name: "capture",
      targets: [
        "CaptureCLI"
      ]
    )
  ],
  dependencies: [],
  targets: [
    .target(
      name: "CaptureCLI",
      dependencies: []
    )
  ]
)
