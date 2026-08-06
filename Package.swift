// swift-tools-version: 6.0
import PackageDescription

// The product is Standfast; the module that models GitHub Actions runners keeps
// the name that describes it. `RunnerKit` says what is inside it — runners,
// their LaunchAgents, their state — and renaming it to match the product would
// trade that for a word that says nothing about runners at all.
let package = Package(
  name: "Standfast",
  defaultLocalization: "en",
  platforms: [.macOS(.v14)],
  targets: [
    .target(name: "RunnerKit", path: "Sources/RunnerKit"),
    .executableTarget(
      name: "Standfast",
      dependencies: ["RunnerKit"],
      path: "Sources/Standfast",
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
      name: "StandfastTests",
      dependencies: ["Standfast", "RunnerKit"],
      path: "Tests/StandfastTests"
    ),
  ]
)
