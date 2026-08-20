import Foundation

/// One `[[runners]]` entry of a gitlab-runner `config.toml`, reduced to what
/// this app needs to find and ask about it.
///
/// There is deliberately nowhere here to put the runner's `token`. That
/// credential can start jobs; this app asks GitLab with its own token from the
/// Keychain, and carrying the runner's around in memory to answer a question
/// nobody asks with it would be all risk and no reader.
public struct GitLabRunnerEntry: Equatable, Sendable {
  /// The runner's id on its GitLab instance — written by gitlab-runner since
  /// 15.0, and the only way to ask the API about *this* runner.
  public let id: Int
  /// Empty when the file gives none; what to show instead is the caller's
  /// decision, the same rule `.runner` files follow.
  public let name: String
  /// The host of the instance this runner reports to. Kept as a host rather
  /// than a URL because it is an identity here, not an address — the API
  /// client builds its own URLs.
  public let instanceHost: String
}

/// Reads the parts of `config.toml` this app uses.
///
/// Not a TOML parser, on purpose. TOML is a large format and gitlab-runner
/// writes a narrow, stable slice of it: top-level keys, `[[runners]]` array
/// tables, and named sub-tables under each runner. A scanner for exactly that
/// shape can say precisely what it does with every line it meets; a hand-rolled
/// "general" parser could not, and pulling in a dependency for four keys would
/// be the tail wagging the dog. Anything outside the known shape is ignored,
/// never guessed at.
public enum GitLabRunnerConfigFile {
  public struct Reading: Equatable, Sendable {
    public let entries: [GitLabRunnerEntry]
    /// Runners the file plainly declares that this app cannot use — no id
    /// (written before gitlab-runner 15.0, or edited by hand), or a url no
    /// host can be read from. Named so the caller can say so, because
    /// dropping a runner the file declares is how half a fleet goes missing
    /// in silence.
    public let skipped: [String]
  }

  public static func entries(in text: String) throws -> [GitLabRunnerEntry] {
    try reading(text).entries
  }

  public static func reading(_ text: String) throws -> Reading {
    var entries: [GitLabRunnerEntry] = []
    var skipped: [String] = []

    var current: [String: String]?
    // Whether the scanner is directly inside `[[runners]]`, as opposed to a
    // sub-table like `[runners.docker]` — whose keys belong to the sub-table,
    // not to the runner. `[runners.docker]` even has a `name` of its own.
    var inRunnerBody = false

    func finish() {
      guard let fields = current else { return }
      current = nil
      let name = fields["name"] ?? ""
      guard let id = fields["id"].flatMap({ Int($0) }) else {
        skipped.append(name)
        return
      }
      guard let url = fields["url"], let host = URL(string: url)?.host else {
        skipped.append(name)
        return
      }
      entries.append(GitLabRunnerEntry(id: id, name: name, instanceHost: host))
    }

    for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
      let line = rawLine.trimmingCharacters(in: .whitespaces)
      if line.hasPrefix("[[") {
        finish()
        if line == "[[runners]]" {
          current = [:]
          inRunnerBody = true
        } else {
          inRunnerBody = false
        }
        continue
      }
      if line.hasPrefix("[") {
        // A sub-table. It still belongs to the current runner, so the entry is
        // not finished — but its keys are not the runner's.
        inRunnerBody = false
        continue
      }
      guard inRunnerBody, current != nil else { continue }
      guard let equals = line.firstIndex(of: "=") else { continue }
      let key = line[..<equals].trimmingCharacters(in: .whitespaces)
      var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
        value = String(value.dropFirst().dropLast())
      }
      current?[key] = value
    }
    finish()

    return Reading(entries: entries, skipped: skipped)
  }
}
