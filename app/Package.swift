// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TTYCat",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "TTYCat", path: "Sources/TTYCat"),
    .testTarget(name: "TTYCatTests", dependencies: ["TTYCat"], path: "Tests/TTYCatTests"),
  ]
)
