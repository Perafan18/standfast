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
  let json =
    #"{"agentId":7,"agentName":"n","gitHubUrl":"https://github.com/a/b","#
    + #""workFolder":"_work"}"#
  #expect(try RunnerConfig(data: Data(json.utf8)).agentId == 7)
}

@Test func survivesAFileMissingItsCosmeticFields() throws {
  // Only agentId and gitHubUrl cannot be reconstructed from anywhere else. If
  // a future runner release renames the rest, the runner must still be found
  // rather than silently disappearing from the menu.
  let data = Data(#"{"agentId":7,"gitHubUrl":"https://github.com/a/b"}"#.utf8)
  let config = try RunnerConfig(data: data)

  #expect(config.agentId == 7)
  #expect(config.agentName == "")
  #expect(config.workFolder == "_work")
}

@Test func survivesCosmeticFieldsThatChangedType() throws {
  // Tolerating a missing field but not one that turned into a number is half
  // a guarantee: either way the value is unusable, and either way losing the
  // runner over it is the wrong trade.
  let data = Data(
    #"{"agentId":7,"gitHubUrl":"https://github.com/a/b","agentName":123,"workFolder":[]}"#
      .utf8)
  let config = try RunnerConfig(data: data)

  #expect(config.agentId == 7)
  #expect(config.agentName == "")
  #expect(config.workFolder == "_work")

  let nullWorkFolder = Data(
    #"{"agentId":7,"gitHubUrl":"https://github.com/a/b","workFolder":null}"#.utf8)
  #expect(try RunnerConfig(data: nullWorkFolder).workFolder == "_work")
}

@Test func keepsEveryWorkFolderTheRunnerItselfAccepts() throws {
  // `config.sh --work` validates nothing but emptiness and the runner joins the
  // value onto its root, so each of these is a machine that takes jobs. Whether
  // one leaves the runner is housekeeping's question, not the file's.
  for folder in ["../outside", "/Volumes/Builds/_work", "./_work", "builds/../_work"] {
    let json =
      #"{"agentId":7,"gitHubUrl":"https://github.com/a/b","workFolder":"\#(folder)"}"#
    #expect(try RunnerConfig(data: Data(json.utf8)).workFolder == folder)
  }
}

@Test func anEmptyWorkFolderFallsBackToTheStandardOne() throws {
  // `config.sh` never writes one. Reading it as the runner's root would aim
  // maintenance at the runner's own files rather than at `_work`.
  let json = #"{"agentId":7,"gitHubUrl":"https://github.com/a/b","workFolder":""}"#
  #expect(try RunnerConfig(data: Data(json.utf8)).workFolder == "_work")
}

@Test func refusesFilesItCannotTrust() {
  // Half a config is worse than none: it would name a runner the API cannot
  // be asked about.
  #expect(throws: (any Error).self) {
    try RunnerConfig(data: Data("not json at all".utf8))
  }
  #expect(throws: (any Error).self) {
    try RunnerConfig(data: Data(#"{"agentName":"n","workFolder":"_work"}"#.utf8))
  }
  #expect(throws: (any Error).self) {
    try RunnerConfig(data: Data(#"{"agentId":7}"#.utf8))
  }
  // The leniency above stops at the two fields nothing can replace.
  #expect(throws: (any Error).self) {
    try RunnerConfig(
      data: Data(#"{"agentId":"7","gitHubUrl":"https://github.com/a/b"}"#.utf8))
  }
  #expect(throws: (any Error).self) {
    try RunnerConfig(data: Data(#"{"agentId":7,"gitHubUrl":null}"#.utf8))
  }
}
