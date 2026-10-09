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
  /// The instance this runner reports to.
  public let instance: GitLabInstance
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

  /// The instances the file's runners report to, each once, in the order the
  /// file first names them.
  public static func instances(in text: String) -> [GitLabInstance] {
    var seen = Set<GitLabInstance>()
    let instances = ((try? entries(in: text)) ?? []).map(\.instance)
    return instances.filter { seen.insert($0).inserted }
  }

  public static func reading(_ text: String) throws -> Reading {
    var entries: [GitLabRunnerEntry] = []
    var skipped: [String] = []

    var current: [String: String]?
    // Whether the scanner is directly inside `[[runners]]`, as opposed to a
    // sub-table like `[runners.docker]` — whose keys belong to the sub-table,
    // not to the runner. `[runners.docker]` even has a `name` of its own.
    var inRunnerBody = false
    // The delimiter of a multi-line string still open. Its lines are a
    // script's text, where `url=` is shell and `[ -d … ]` is not a table.
    var openString: String?

    func finish() {
      guard let fields = current else { return }
      current = nil
      let name = fields["name"] ?? ""
      guard let id = fields["id"].flatMap({ Int($0) }) else {
        skipped.append(name)
        return
      }
      guard let instance = fields["url"].flatMap(GitLabInstance.init(url:)) else {
        skipped.append(name)
        return
      }
      entries.append(GitLabRunnerEntry(id: id, name: name, instance: instance))
    }

    // On any newline, because Swift reads "\r\n" as one Character: a file
    // saved with CRLF splits on "\n" into a single line and loses every runner.
    let lines = text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline)
    for rawLine in lines {
      let line = rawLine.trimmingCharacters(in: blank)
      if let delimiter = openString {
        if line.contains(delimiter) { openString = nil }
        continue
      }
      // Before the opener check: a commented-out `script = '''` opens nothing,
      // and taking it for an opener would swallow every runner after it.
      if line.hasPrefix("#") { continue }
      if line.hasPrefix("[[") {
        finish()
        if withoutComment(line) == "[[runners]]" {
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
      guard let equals = line.firstIndex(of: "=") else { continue }
      let key = line[..<equals].trimmingCharacters(in: .whitespaces)
      var value = line[line.index(after: equals)...].trimmingCharacters(in: .whitespaces)
      if let delimiter = ["\"\"\"", "'''"].first(where: value.hasPrefix),
        !value.dropFirst(delimiter.count).contains(delimiter)
      {
        openString = delimiter
        continue
      }
      guard inRunnerBody, current != nil else { continue }
      if value.hasPrefix("\""), value.hasSuffix("\""), value.count >= 2 {
        value = String(value.dropFirst().dropLast())
      }
      current?[key] = value
    }
    finish()

    return Reading(entries: entries, skipped: skipped)
  }

  /// Whitespace, and a byte-order mark, which Foundation does not count as
  /// whitespace and an editor may leave in front of the first header.
  private static let blank = CharacterSet.whitespaces.union(
    CharacterSet(charactersIn: "\u{FEFF}"))

  /// A header without a trailing `# comment`. Table names this scanner looks
  /// for never contain `#`, so the first one starts the comment.
  private static func withoutComment(_ line: String) -> String {
    let header = line.split(separator: "#", maxSplits: 1).first ?? ""
    return header.trimmingCharacters(in: .whitespaces)
  }
}
