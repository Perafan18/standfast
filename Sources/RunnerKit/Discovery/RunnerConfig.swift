import Foundation

/// The `.runner` file the agent writes into its own directory at configure
/// time. It is the authoritative description of a runner: which GitHub scope
/// it belongs to and, crucially, its `agentId` — the only way to ask the API
/// about *this* runner rather than whichever one happens to be listed first.
public struct RunnerConfig: Decodable, Equatable, Sendable {
  public let agentId: Int
  public let agentName: String
  public let gitHubUrl: String
  public let workFolder: String
}

extension RunnerConfig {
  public init(data: Data) throws {
    try self.init(decoding: data)
  }

  public init(contentsOf url: URL) throws {
    try self.init(decoding: Data(contentsOf: url))
  }

  private init(decoding data: Data) throws {
    // The runner writes `.runner` with a UTF-8 BOM. JSONDecoder treats those
    // three bytes as garbage before the opening brace and refuses the file,
    // so they come off first.
    let bom: [UInt8] = [0xEF, 0xBB, 0xBF]
    let payload = data.starts(with: bom) ? data.dropFirst(bom.count) : data.dropFirst(0)
    self = try JSONDecoder().decode(RunnerConfig.self, from: Data(payload))
  }
}
