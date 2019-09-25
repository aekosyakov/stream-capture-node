// swift-tools-version:5.1
// The swift-tools-version declares the minimum version of Swift required to build this package.

import PackageDescription

let package = Package(
  name: "CaptureCLI",
  platforms: [
    .macOS(.v10_12)
  ],
  products: [
    .executable(
      name: "capture",
      targets: [
        "CaptureCLI"
      ]
    )
  ],
  dependencies: [
    .package(url: "https://github.com/aekosyakov/ScreenCapture.git", from: "1.0.2")
  ],
  targets: [
    .target(
      name: "CaptureCLI",
      dependencies: [
        "ScreenCapture"
      ]
    )
  ]
)
