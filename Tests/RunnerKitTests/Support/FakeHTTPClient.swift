import Foundation

@testable import RunnerKit

/// Replays canned HTTP answers and records every request, headers included.
///
/// Keyed by URL and consumed in order, because the behaviour worth testing
/// here is what happens on the *second* question about the same runner: a
/// conditional request that GitHub answers 304 is the whole reason this client
/// can poll every fifteen seconds without spending its rate limit.
final class FakeHTTPClient: HTTPPerforming, @unchecked Sendable {
  struct Request: Equatable {
    let url: URL
    let headers: [String: String]
  }

  struct Unreachable: Error {}

  private(set) var requests: [Request] = []
  private var queued: [URL: [HTTPResponse]] = [:]
  /// Thrown instead of answering. A Mac with no network, in one flag.
  var offline = false

  init(_ answers: [URL: [HTTPResponse]] = [:]) { queued = answers }

  func blockingGet(_ url: URL, headers: [String: String]) throws -> HTTPResponse {
    requests.append(Request(url: url, headers: headers))
    if offline { throw HTTPError.unreachable(underlying: Unreachable()) }
    guard var remaining = queued[url], !remaining.isEmpty else {
      // Deliberately not a default 200: a test whose URL is wrong by one
      // character must fail loudly rather than receive a healthy answer.
      throw HTTPError.unreachable(underlying: Unreachable())
    }
    let answer = remaining.removeFirst()
    // The last answer stays, so a test that only cares about one response does
    // not have to queue one per call.
    queued[url] = remaining.isEmpty ? [answer] : remaining
    return answer
  }
}

extension HTTPResponse {
  static func ok(_ json: String, etag: String? = nil) -> Self {
    Self(
      statusCode: 200, body: Data(json.utf8),
      headers: etag.map { ["Etag": $0] } ?? [:])
  }

  static func status(_ code: Int, headers: [String: String] = [:]) -> Self {
    Self(statusCode: code, body: Data(), headers: headers)
  }
}
