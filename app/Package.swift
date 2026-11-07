// swift-tools-version: 5.9
import PackageDescription

let package = Package(
  name: "TTYCat",
  platforms: [.macOS(.v14)],
  dependencies: [
    // The app updating itself: only a release starts it (AppUpdater.swift). Pinned: a new version is a choice.
    .package(url: "https://github.com/sparkle-project/Sparkle", exact: "2.10.1"),
  ],
  targets: [
    .executableTarget(
      name: "TTYCat",
      dependencies: [.product(name: "Sparkle", package: "Sparkle")],
      path: "Sources/TTYCat",
      // Sparkle.framework is in the app's Contents/Frameworks: app/build.sh puts it there.
      linkerSettings: [.unsafeFlags(["-Xlinker", "-rpath", "-Xlinker", "@executable_path/../Frameworks"])]
    ),
    .testTarget(name: "TTYCatTests", dependencies: ["TTYCat"], path: "Tests/TTYCatTests"),
  ]
)
