import Foundation

/// The one implementation of `HTTPPerforming` that actually reaches GitHub.
///
/// Blocking on purpose, like `ProcessCommandRunner` beside it: the caller is a
/// state resolver that composes a remote answer with a local probe
/// synchronously. It must therefore be called from a thread that is allowed to
/// block — never the main actor, and never the cooperative pool behind a plain
/// `Task`.
public struct URLSessionHTTPClient: HTTPPerforming {
  private let session: URLSession
  private let timeout: TimeInterval

  /// The same thirty seconds `ProcessCommandRunner` gives `gh`, so a GitHub
  /// that has gone quiet costs the same wait whichever path asked it.
  public static let defaultTimeout: TimeInterval = 30

  public init(
    session: URLSession = URLSessionHTTPClient.standardSession,
    timeout: TimeInterval = URLSessionHTTPClient.defaultTimeout
  ) {
    self.session = session
    self.timeout = timeout
  }

  /// Deliberately without an HTTP cache.
  ///
  /// URLSession will otherwise answer a conditional request by replaying the
  /// stored 200 and never telling the caller a 304 happened. Every conditional
  /// request in `GitHubAPIClient` exists to see that 304 — it is what keeps a
  /// fifteen-second poll inside a personal token's hourly budget — so a cache
  /// that helpfully hides it would silently undo the entire strategy, and the
  /// symptom would be a rate limit weeks later.
  public static var standardSession: URLSession {
    let configuration = URLSessionConfiguration.ephemeral
    configuration.urlCache = nil
    configuration.requestCachePolicy = .reloadIgnoringLocalCacheData
    return URLSession(configuration: configuration)
  }

  public func blockingGet(_ url: URL, headers: [String: String]) throws -> HTTPResponse {
    var request = URLRequest(url: url, timeoutInterval: timeout)
    request.httpMethod = "GET"
    // Belt and braces with `standardSession`: a caller that injects its own
    // session must not be able to reintroduce the cache that would swallow
    // every 304.
    request.cachePolicy = .reloadIgnoringLocalCacheData
    for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }

    let outcome = Outcome()
    let waiting = DispatchSemaphore(value: 0)
    let task = session.dataTask(with: request) { data, response, error in
      outcome.finish(data: data, response: response, error: error)
      waiting.signal()
    }
    task.resume()
    waiting.wait()
    return try outcome.result()
  }

  /// Carries the completion handler's three values back to the thread that is
  /// blocked waiting for them. A class because the closure has to write where
  /// the caller can read, and the semaphore is what orders the two.
  private final class Outcome: @unchecked Sendable {
    private var data: Data?
    private var response: URLResponse?
    private var error: (any Error)?

    struct NotHTTP: Error {}

    func finish(data: Data?, response: URLResponse?, error: (any Error)?) {
      self.data = data
      self.response = response
      self.error = error
    }

    func result() throws -> HTTPResponse {
      if let error { throw HTTPError.unreachable(underlying: error) }
      // No status code exists here. Inventing one — 0, or 503 — would put a
      // lie one layer up, where it would be read as something GitHub said.
      guard let http = response as? HTTPURLResponse else {
        throw HTTPError.unreachable(underlying: NotHTTP())
      }
      var headers: [String: String] = [:]
      for (name, value) in http.allHeaderFields {
        guard let name = name as? String, let value = value as? String else { continue }
        headers[name] = value
      }
      return HTTPResponse(
        statusCode: http.statusCode, body: data ?? Data(), headers: headers)
    }
  }
}
