import Foundation
import Testing

@testable import RunnerKit

/// Answers every request from instructions filed under its URL, so the class
/// under test is the real one and the seam is below it rather than around it.
///
/// Keyed by URL rather than held in one static answer: these tests run in
/// parallel, and a single shared answer means whichever test writes last wins
/// for all of them. That is not a hypothetical — the first version of this file
/// failed exactly that way, with three tests receiving a fourth test's
/// transport failure.
private final class StubProtocol: URLProtocol, @unchecked Sendable {
  struct Instruction {
    var status = 200
    var body = Data()
    var headers: [String: String] = [:]
    var failure: (any Error)?
    /// Sends the body a byte at a time, this far apart, so the connection is
    /// never idle long enough for a per-packet timeout to fire.
    var trickle: TimeInterval?
    /// Answered as a redirect to here, the way a server's `Location` is.
    var redirect: URL?
  }

  struct Refused: Error {}

  private static let lock = NSLock()
  nonisolated(unsafe) private static var instructions: [URL: Instruction] = [:]
  nonisolated(unsafe) private static var received: [URL: [URLRequest]] = [:]

  static func expect(_ url: URL, _ instruction: Instruction) {
    lock.lock()
    defer { lock.unlock() }
    instructions[url] = instruction
    received[url] = []
  }

  static func requests(to url: URL) -> [URLRequest] {
    lock.lock()
    defer { lock.unlock() }
    return received[url] ?? []
  }

  private static func instruction(for url: URL) -> Instruction {
    lock.lock()
    defer { lock.unlock() }
    return instructions[url] ?? Instruction()
  }

  private static func record(_ request: URLRequest) {
    guard let url = request.url else { return }
    lock.lock()
    defer { lock.unlock() }
    received[url, default: []].append(request)
  }

  override class func canInit(with request: URLRequest) -> Bool { true }
  override class func canonicalRequest(for request: URLRequest) -> URLRequest { request }

  override func startLoading() {
    Self.record(request)
    let instruction = Self.instruction(for: request.url!)
    if let failure = instruction.failure {
      client?.urlProtocol(self, didFailWithError: failure)
      return
    }
    let response = HTTPURLResponse(
      url: request.url!, statusCode: instruction.status,
      httpVersion: "HTTP/1.1", headerFields: instruction.headers)!
    if let target = instruction.redirect {
      // What URLSession itself does with a 3xx: the same request, headers and
      // all, aimed somewhere else.
      var redirected = request
      redirected.url = target
      client?.urlProtocol(self, wasRedirectedTo: redirected, redirectResponse: response)
    }
    client?.urlProtocol(self, didReceive: response, cacheStoragePolicy: .notAllowed)
    if let interval = instruction.trickle {
      drip(instruction.body, every: interval)
      return
    }
    client?.urlProtocol(self, didLoad: instruction.body)
    client?.urlProtocolDidFinishLoading(self)
  }

  private let stopLock = NSLock()
  private var stopped = false

  private func drip(_ bytes: Data, every interval: TimeInterval) {
    DispatchQueue.global().asyncAfter(deadline: .now() + interval) { [self] in
      stopLock.lock()
      let gone = stopped
      stopLock.unlock()
      guard !gone else { return }
      guard let byte = bytes.first else {
        client?.urlProtocolDidFinishLoading(self)
        return
      }
      client?.urlProtocol(self, didLoad: Data([byte]))
      drip(bytes.dropFirst(), every: interval)
    }
  }

  override func stopLoading() {
    stopLock.lock()
    stopped = true
    stopLock.unlock()
  }
}

private func subject(
  timeout: TimeInterval = URLSessionHTTPClient.defaultTimeout
) -> URLSessionHTTPClient {
  let configuration = URLSessionConfiguration.ephemeral
  configuration.protocolClasses = [StubProtocol.self]
  return URLSessionHTTPClient(
    session: URLSession(configuration: configuration), timeout: timeout)
}

/// One per test, so no test can be answered by another's instructions.
private func distinctURL(_ name: String) -> URL {
  URL(string: "https://api.github.com/stub/\(name)")!
}

@Test func handsBackTheStatusBodyAndHeadersItWasGiven() throws {
  let url = distinctURL("answer")
  StubProtocol.expect(
    url,
    .init(status: 200, body: Data(#"{"ok":true}"#.utf8), headers: ["Etag": #""tag""#]))

  let response = try subject().blockingGet(url, headers: [:])

  #expect(response.statusCode == 200)
  #expect(String(decoding: response.body, as: UTF8.self) == #"{"ok":true}"#)
  #expect(response.header("etag") == #""tag""#)
}

@Test func sendsEveryHeaderItWasAskedTo() throws {
  let url = distinctURL("headers")
  StubProtocol.expect(url, .init())

  _ = try subject().blockingGet(
    url, headers: ["Authorization": "Bearer x", "If-None-Match": #""tag""#])

  let sent = StubProtocol.requests(to: url)[0]
  #expect(sent.value(forHTTPHeaderField: "Authorization") == "Bearer x")
  #expect(sent.value(forHTTPHeaderField: "If-None-Match") == #""tag""#)
}

@Test func aTransportFailureIsUnreachableRatherThanAStatusCode() throws {
  // No network, no DNS, no TLS. There is no status code to report, and
  // inventing one — 0, or 503 — would put a lie in the layer above, where it
  // would be read as something GitHub said.
  let url = distinctURL("offline")
  StubProtocol.expect(url, .init(failure: StubProtocol.Refused()))

  #expect(throws: HTTPError.self) { try subject().blockingGet(url, headers: [:]) }
}

@Test func a304IsDeliveredRatherThanQuietlyTurnedIntoTheCachedBody() throws {
  // URLSession's own HTTP cache will happily answer a conditional request by
  // replaying the stored 200 and never telling the caller a 304 happened. This
  // client's whole rate-limit strategy depends on seeing the 304 itself, so
  // caching is turned off underneath rather than reasoned about.
  let url = distinctURL("unchanged")
  StubProtocol.expect(url, .init(status: 304))

  #expect(try subject().blockingGet(url, headers: [:]).statusCode == 304)
}

@Test func aServerThatNeverGoesQuietStillCostsNoMoreThanTheTimeout() throws {
  // A request's own timeout is per packet, so a proxy dripping bytes resets it
  // indefinitely, and every runner behind this one in the scan waits too.
  let url = distinctURL("trickle")
  StubProtocol.expect(url, .init(body: Data(repeating: 0x20, count: 30), trickle: 0.1))
  let started = Date()

  #expect(throws: HTTPError.self) {
    try subject(timeout: 0.5).blockingGet(url, headers: [:])
  }
  #expect(Date().timeIntervalSince(started) < 2)
}

@Test func aRedirectToAnotherOriginIsNotFollowed() throws {
  // Every request here carries a credential, and URLSession copies custom
  // headers onto a redirect: a PRIVATE-TOKEN would follow a 302 to any host.
  // Another scheme or port is another server too.
  let elsewhere = [
    "https://elsewhere.example/stub/away", "http://api.github.com/stub/away-plain",
    "https://api.github.com:8443/stub/away-port",
  ].map { URL(string: $0)! }
  for (index, target) in elsewhere.enumerated() {
    let url = distinctURL("away-\(index)")
    StubProtocol.expect(url, .init(status: 302, redirect: target))
    StubProtocol.expect(target, .init())

    let response = try subject().blockingGet(url, headers: ["PRIVATE-TOKEN": "glpat-x"])

    #expect(response.statusCode == 302, "\(target)")
    #expect(StubProtocol.requests(to: target).isEmpty, "\(target)")
  }
}

@Test func aRedirectWithinTheOriginIsStillFollowed() throws {
  // GitHub answers a renamed repository's API path with a 301 on the same
  // host, and that move is one to follow.
  let url = distinctURL("moved")
  let moved = distinctURL("moved-here")
  StubProtocol.expect(url, .init(status: 301, redirect: moved))
  StubProtocol.expect(moved, .init(status: 200, body: Data("{}".utf8)))

  let response = try subject().blockingGet(url, headers: [:])

  #expect(response.statusCode == 200)
  #expect(StubProtocol.requests(to: moved).count == 1)
}
