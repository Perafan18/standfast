import Foundation

/// A GitLab instance as a runner's `config.toml` names it: scheme, host, port
/// and path. A self-managed GitLab on `:8443`, under `/gitlab`, over http or
/// at an IPv6 literal is somewhere else once any of them is dropped.
public struct GitLabInstance: Hashable, Sendable {
  /// Where the pages and the API live, with no trailing slash. Built once from
  /// parts that already parsed, so nothing downstream holds an address that
  /// might not.
  public let baseURL: URL
  /// The instance's identity, and how it is shown: host, port and path, with
  /// the scheme only when it is not https. A default instance reads as its
  /// bare host, so labels built from it keep their old spelling.
  public let name: String

  /// Nil for anything that is not an http or https URL with a host.
  public init?(url text: String) {
    guard let parsed = URLComponents(string: text),
      let scheme = parsed.scheme?.lowercased(), scheme == "https" || scheme == "http",
      // The encoded spelling keeps an IPv6 literal inside its brackets.
      let host = parsed.percentEncodedHost?.lowercased(), !host.isEmpty
    else { return nil }
    var path = parsed.percentEncodedPath
    while path.hasSuffix("/") { path.removeLast() }
    // An explicit default port is the same instance, and so the same token.
    let port = parsed.port == (scheme == "https" ? 443 : 80) ? nil : parsed.port

    // Rebuilt rather than kept, so credentials, a query or a fragment written
    // into the url never ride along on an API request.
    var base = URLComponents()
    base.scheme = scheme
    base.percentEncodedHost = host
    base.port = port
    base.percentEncodedPath = path
    guard let baseURL = base.url else { return nil }
    self.baseURL = baseURL
    let authority = host + (port.map { ":\($0)" } ?? "")
    name = (scheme == "https" ? "" : "http://") + authority + path
  }

  /// Whether requests to it are encrypted. Only these are sent a token.
  public var isServedOverHTTPS: Bool { baseURL.scheme == "https" }

  /// `GET /api/v4/runners/{id}`, under whatever path the instance is served
  /// from.
  public func runnerURL(id: Int) -> URL {
    baseURL.appending(path: "api/v4/runners/\(id)")
  }
}
