// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RunnerMenubar",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "RunnerKit", path: "Sources/RunnerKit"),
    .executableTarget(
      name: "RunnerMenubar",
      dependencies: ["RunnerKit"],
      path: "Sources/RunnerMenubar",
      resources: [.process("Resources")]
    ),
    .testTarget(
      name: "RunnerKitTests",
      dependencies: ["RunnerKit"],
      path: "Tests/RunnerKitTests",
      resources: [.copy("Fixtures")]
    ),
    // Tests the executable target directly, which SwiftPM allows on macOS.
    // The alternative — a library target holding the presentation logic — buys
    // nothing here: the menu's copy, its per-runner button rules and the
    // settling window are all plain values, and moving them out would only put
    // a package boundary between them and the one app that uses them.
    .testTarget(
      name: "RunnerMenubarTests",
      dependencies: ["RunnerMenubar", "RunnerKit"],
      path: "Tests/RunnerMenubarTests"
    ),
  ]
)
