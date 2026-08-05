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
  ]
)
