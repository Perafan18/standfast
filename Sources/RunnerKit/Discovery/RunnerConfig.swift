import Foundation

/// The `.runner` file the agent writes into its own directory at configure
/// time. It is the authoritative description of a runner: which GitHub scope
/// it belongs to and, crucially, its `agentId` — the only way to ask the API
/// about *this* runner rather than whichever one happens to be listed first.
struct RunnerConfig: Decodable, Equatable, Sendable {
  /// Identifies this runner to the API. Nothing else can stand in for it, so
  /// a file without one does not describe a runner we can ask about.
  let agentId: Int
  /// Empty when the file carries no usable name: absent, null, or not a
  /// string at all. What to show instead is the caller's decision.
  let agentName: String
  let gitHubUrl: String
  let workFolder: String

  enum CodingKeys: String, CodingKey {
    case agentId, agentName, gitHubUrl, workFolder
  }

  init(from decoder: any Decoder) throws {
    let container = try decoder.container(keyedBy: CodingKeys.self)
    // Only the two fields that cannot be reconstructed from anywhere else are
    // required. Demanding the cosmetic ones would mean a future runner release
    // renaming one of them empties the menu, with nothing on screen to say so.
    agentId = try container.decode(Int.self, forKey: .agentId)
    gitHubUrl = try container.decode(String.self, forKey: .gitHubUrl)
    agentName = container.cosmeticString(forKey: .agentName, default: "")
    // Taken as written, absolute and `..` included: `config.sh --work` accepts
    // any non-empty value and the runner works from it. Whether it stays inside
    // the runner is for housekeeping to prove, not a reason to lose the runner.
    let decodedWorkFolder = container.cosmeticString(forKey: .workFolder, default: "_work")
    workFolder = decodedWorkFolder.isEmpty ? "_work" : decodedWorkFolder
  }
}

extension KeyedDecodingContainer {
  /// Reads a field the app can do without. Absent, null and changed-type all
  /// come back as the default, because the runner is worth more than any of
  /// these values and all three failures are equally unusable.
  fileprivate func cosmeticString(forKey key: Key, default fallback: String) -> String {
    // One `??` covers all three failures: `try?` flattens the optional that
    // `decodeIfPresent` returns, so an absent key, an explicit null and a value
    // of the wrong type all arrive here as nil.
    (try? decodeIfPresent(String.self, forKey: key)) ?? fallback
  }
}

extension RunnerConfig {
  init(data: Data) throws {
    try self.init(decoding: data)
  }

  init(contentsOf url: URL) throws {
    try self.init(decoding: Data(contentsOf: url))
  }

  private init(decoding data: Data) throws {
    // The runner writes `.runner` with a UTF-8 BOM. JSONDecoder treats those
    // three bytes as garbage before the opening brace and refuses the file,
    // so they come off first.
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    let payload = data.starts(with: bom) ? data.dropFirst(bom.count) : data[...]
    self = try JSONDecoder().decode(RunnerConfig.self, from: Data(payload))
  }
}
