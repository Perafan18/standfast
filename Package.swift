// swift-tools-version: 6.0
import PackageDescription

let package = Package(
  name: "RunnerMenubar",
  platforms: [.macOS(.v14)],
  targets: [
    .executableTarget(name: "RunnerMenubar", path: "Sources/RunnerMenubar")
  ]
)
