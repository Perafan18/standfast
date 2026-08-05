import Foundation
import Testing

@testable import RunnerKit

private func fixture(_ name: String) -> URL {
  Bundle.module.url(
    forResource: name, withExtension: "plist",
    subdirectory: "Fixtures")!
}

@Test func readsLabelAndWorkingDirectory() throws {
  let descriptor = try LaunchAgentDescriptor(
    contentsOf: fixture("actions.runner.acme-widget-factory.build-mac"))
  #expect(descriptor.label == "actions.runner.acme-widget-factory.build-mac")
  #expect(descriptor.workingDirectory.path == "/Users/ci/actions-runner")
}

/// Both formats launchd accepts. The runner ships XML, but `plutil -convert`
/// and several MDM tools rewrite agents as binary, and the file stops being
/// readable as text without anything announcing it.
@Test(arguments: [
  PropertyListSerialization.PropertyListFormat.xml,
  PropertyListSerialization.PropertyListFormat.binary,
])
func ignoresTheKeysWeDoNotNeed(
  format: PropertyListSerialization.PropertyListFormat
) throws {
  // Real plists also carry program arguments, log paths, environment and
  // process options, and which of them are present varies between runner
  // releases. Decoding must not depend on that set.
  let url = URL(fileURLWithPath: NSTemporaryDirectory())
    .appendingPathComponent("launch-agent-\(UUID().uuidString).plist")
  defer { try? FileManager.default.removeItem(at: url) }
  let plist: [String: Any] = [
    "Label": "actions.runner.acme-widget-factory.build-mac",
    "WorkingDirectory": "/Users/ci/actions-runner",
    "StandardOutPath": "/Users/ci/actions-runner/stdout.log",
    "EnvironmentVariables": ["PATH": "/usr/bin"],
    "KeyFromSomeFutureRunnerRelease": true,
  ]
  try PropertyListSerialization.data(fromPropertyList: plist, format: format, options: 0)
    .write(to: url)

  let descriptor = try LaunchAgentDescriptor(contentsOf: url)
  #expect(descriptor.label == "actions.runner.acme-widget-factory.build-mac")
  #expect(descriptor.workingDirectory.path == "/Users/ci/actions-runner")
}
