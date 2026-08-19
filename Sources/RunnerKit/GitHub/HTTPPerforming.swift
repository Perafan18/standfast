import Foundation

/// What a finished HTTP request left behind.
///
/// Headers are kept because two of them decide whether this app can poll at
/// all: `Etag`, which makes the next question free, and the rate-limit family,
/// which says how many questions are left.
public struct HTTPResponse: Sendable {
  public let statusCode: Int
  public let body: Data
  public let headers: [String: String]

  public init(statusCode: Int, body: Data, headers: [String: String] = [:]) {
    self.statusCode = statusCode
    self.body = body
    self.headers = headers
  }

  /// Case-insensitively, because HTTP header names are and every layer spells
  /// them differently — `Etag`, `ETag`, `etag` all reach here. A lookup that
  /// matched one spelling would simply never find the tag, and the symptom
  /// would be a rate limit weeks later rather than a failure now.
  public func header(_ name: String) -> String? {
    headers.first { $0.key.caseInsensitiveCompare(name) == .orderedSame }?.value
  }
}

public enum HTTPError: Error {
  /// The request never produced a response: no network, DNS, TLS, a timeout.
  /// The underlying error is kept whole for whoever has to explain it.
  case unreachable(underlying: any Error)
}

/// The seam every HTTP request goes through.
///
/// Blocking, like `CommandRunning` beside it and for the same reason: the one
/// caller is `RunnerStateResolver`, which composes a remote answer with a local
/// probe synchronously and hops once for both. An async facade here would buy
/// nothing and would put a suspension point in the middle of that composition.
public protocol HTTPPerforming: Sendable {
  func blockingGet(_ url: URL, headers: [String: String]) throws -> HTTPResponse
}
