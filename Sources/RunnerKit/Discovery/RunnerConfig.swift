import Foundation

/// The `.runner` file the agent writes into its own directory at configure
/// time. It is the authoritative description of a runner: which GitHub scope
/// it belongs to and, crucially, its `agentId` — the only way to ask the API
/// about *this* runner rather than whichever one happens to be listed first.
struct RunnerConfig: Decodable, Equatable, Sendable {
  /// Identifies this runner to the API. Nothing else can stand in for it, so
  /// a file without one does not describe a runner we can ask about.
  let agentId: Int
  /// Empty when the file carries no name. Discovery falls back to the
  /// LaunchAgent label so that what reaches the menu is never blank.
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
    agentName = try container.decodeIfPresent(String.self, forKey: .agentName) ?? ""
    workFolder =
      try container.decodeIfPresent(String.self, forKey: .workFolder) ?? "_work"
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
