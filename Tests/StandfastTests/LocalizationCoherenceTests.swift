import Foundation
import Testing

@testable import Standfast

private func temporaryLocalisationBundle(
  in root: URL, language: String, entries: [String: String]
) throws -> Bundle {
  let directory = root.appendingPathComponent("\(language).lproj", isDirectory: true)
  try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
  let data = try PropertyListSerialization.data(
    fromPropertyList: entries, format: .xml, options: 0)
  try data.write(to: directory.appendingPathComponent("Localizable.strings"))
  return try #require(Bundle(url: directory))
}

@Test func incompleteCataloguesCannotComposeAMixedRuntimeLanguage() throws {
  // A damaged first catalogue must not supply the English actions while a
  // damaged second catalogue supplies Spanish status copy. Neither catalogue
  // is a valid language pack, so the only coherent degradation is the complete
  // built-in English table.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-localisation-coherence-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  let englishActionOnly = try temporaryLocalisationBundle(
    in: root.appendingPathComponent("english", isDirectory: true),
    language: "en", entries: ["menu.controlCenter": "Open Standfast"])
  let spanishStateOnly = try temporaryLocalisationBundle(
    in: root.appendingPathComponent("spanish", isDirectory: true),
    language: "es", entries: ["state.idle": "Listo — sin trabajo ahora mismo"])
  for candidates in [
    [englishActionOnly, spanishStateOnly],
    [spanishStateOnly, englishActionOnly],
  ] {
    #expect(L10n.t("menu.controlCenter", in: candidates) == "Open Standfast")
    #expect(L10n.t("state.idle", in: candidates) == L10n.english["state.idle"])
  }
}

@Test func aCatalogueThatReturnsARawKeyCannotBecomeTheRuntimeLanguagePack() throws {
  // A catalogue can contain every key and still be damaged: Bundle considers a
  // key mapped to itself a successful lookup. Reject the whole pack so one raw
  // state cannot sit beside otherwise-English actions.
  let root = FileManager.default.temporaryDirectory.appendingPathComponent(
    "standfast-localisation-raw-key-\(UUID().uuidString)", isDirectory: true)
  defer { try? FileManager.default.removeItem(at: root) }

  var invalidEnglish = L10n.english
  invalidEnglish["state.idle"] = "state.idle"
  let rawKeyPack = try temporaryLocalisationBundle(
    in: root.appendingPathComponent("invalid", isDirectory: true),
    language: "en", entries: invalidEnglish)

  let resourceBundle = try #require(L10n.resourceBundle)
  let spanishPath = try #require(
    resourceBundle.path(
      forResource: "Localizable", ofType: "strings", inDirectory: nil,
      forLocalization: "es"))
  let spanish = try #require(
    NSDictionary(contentsOfFile: spanishPath) as? [String: String])
  let spanishPack = try temporaryLocalisationBundle(
    in: root.appendingPathComponent("valid", isDirectory: true),
    language: "es", entries: spanish)
  let candidates = [rawKeyPack, spanishPack]

  #expect(L10n.t("menu.controlCenter", in: candidates) == "Abrir Standfast")
  #expect(L10n.t("state.idle", in: candidates) == spanish["state.idle"])
}
