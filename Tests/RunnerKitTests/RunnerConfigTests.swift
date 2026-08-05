import Foundation
import Testing

@testable import RunnerKit

@Test func decodesRunnerConfigDespiteUTF8BOM() throws {
  let url = Bundle.module.url(
    forResource: "runner-with-bom", withExtension: "json",
    subdirectory: "Fixtures")!
  let config = try RunnerConfig(contentsOf: url)

  #expect(config.agentId == 21)
  #expect(config.agentName == "mac-mini-m4")
  #expect(config.gitHubUrl == "https://github.com/acme/widget-factory")
  #expect(config.workFolder == "_work")
}

@Test func plainJSONWithoutBOMStillDecodes() throws {
  let data = Data(
    #"{"agentId":7,"agentName":"n","gitHubUrl":"https://github.com/a/b","workFolder":"_work"}"#
      .utf8)
  #expect(try RunnerConfig(data: data).agentId == 7)
}
