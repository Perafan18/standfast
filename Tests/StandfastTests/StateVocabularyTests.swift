import Foundation
import RunnerKit
import Testing

@testable import Standfast

/// The vocabulary the two blind reviews took apart.
///
/// Codex, shown the app with no context at all: *"parece diseñada por alguien
/// que ya conoce el modelo interno. Está visualmente ordenada y conceptualmente
/// subexplicada."* These tests fix the three decisions that came out of it —
/// D-R16, D-R17 and D-R18 — because each one is a sentence somebody can
/// quietly reword back into ambiguity.

// MARK: - D-R18: the idle state stops contradicting itself

@Test func theIdleStateNoLongerCallsARunningRunnerInactive() {
  // "Inactivo — listo para trabajos" argued with itself: in plain Spanish
  // "inactivo" is *switched off*. Codex had to work the real meaning out from
  // which buttons were disabled, and named it his first reason not to
  // recommend the app — above anything visual.
  let idle = DisplayState.resolved(.idle).summary

  #expect(idle == L10n.stateIdle)
  #expect(!idle.lowercased().contains("inactiv"))
  #expect(!idle.lowercased().contains("idle"))
  // The badge already said the right word. The sentence now agrees with it.
  #expect(idle.contains(DisplayState.resolved(.idle).shortSummary))
}

// MARK: - D-R16: the layers get named when they disagree

@Test func aStateThatOnlyGitHubCouldNotAnswerSaysTheLocalHalfIsFine() {
  // The resolver reaches these three only after `launchctl` answered *yes*:
  // it short-circuits to `.stopped` when the agent is not loaded. So "running
  // locally" is not a guess here — it is guaranteed by the path taken, and the
  // window is entitled to say it.
  for reason in [UnknownReason.cliUnavailable, .notAuthenticated, .noAnswer] {
    let summary = DisplayState.resolved(.unknown(reason)).summary

    #expect(summary.contains(L10n.stateLayerRunningLocally), "\(reason)")
    #expect(summary.contains(L10n.stateLayerGitHubSilent), "\(reason)")
  }
}

@Test func theOneStateWhereTheLocalHalfIsTheProblemSaysSoInstead() {
  // `serviceStateUnreadable` is the mirror image: launchctl is what went
  // quiet. Saying "running locally" here would be the invention the other
  // three avoid.
  let summary = DisplayState.resolved(.unknown(.serviceStateUnreadable)).summary

  #expect(!summary.contains(L10n.stateLayerRunningLocally))
  #expect(summary.contains(L10n.stateLayerLocalUnreadable))
}

@Test func everyUnknownStateStillEndsWithSomethingToDoAboutIt() {
  // Naming the layer must not cost the instruction. Each of these existed to
  // tell somebody what to try next.
  for reason in [
    UnknownReason.cliUnavailable, .notAuthenticated, .noAnswer,
    .serviceStateUnreadable, .tokenRefused, .tokenUnreadable,
  ] {
    let summary = DisplayState.resolved(.unknown(reason)).summary
    #expect(summary.contains("—"), "\(reason)")
    let instruction = summary.split(separator: "—").last.map(String.init) ?? ""
    #expect(instruction.trimmingCharacters(in: .whitespaces).count > 10, "\(reason)")
  }
}

@Test func agreeingLayersAreStillOneSentence() {
  // The rule is "name them when they disagree". A healthy runner has nothing
  // to disambiguate, and paying for the layers there would turn a three-second
  // glance into a table.
  for state in [RunnerState.idle, .busy, .stopped] {
    let summary = DisplayState.resolved(state).summary
    #expect(!summary.contains(L10n.stateLayerGitHubSilent), "\(state)")
    #expect(!summary.contains(L10n.stateLayerLocalUnreadable), "\(state)")
  }
  // Disconnected is the one that already did it right, and keeps doing it.
  #expect(DisplayState.resolved(.disconnected).summary.contains(","))
}

// MARK: - D-R17: the verbs say what they act on

@Test func theServiceButtonsNameWhatTheyStop() {
  // Codex: "`Parar` puede leerse como dejar de aceptar trabajos, cancelar
  // limpiamente este job, o detener el servicio". The confirmation dialog does
  // explain it — after the click. The button now says it before.
  let card = RunnerCardPresentation.building(
    snapshot("build-mac", display: .resolved(.idle)), measurement: nil,
    latestRelease: nil, isMaintenanceWorking: false, maintenanceNotice: nil,
    now: Date(timeIntervalSince1970: 1_785_962_174), fleetSize: 1)

  #expect(card.action(.start)?.label == L10n.serviceStart)
  #expect(card.action(.stop)?.label == L10n.serviceStop)
  #expect(card.action(.restart)?.label == L10n.serviceRestart)
  // And each one is longer than the bare verb it replaced, which is the whole
  // point: the object is what was missing.
  #expect(L10n.serviceStop.count > L10n.stop.count)
}

@Test func theQuickMenuKeepsTheShortVerb() {
  // 249 pt wide with a hard row budget: the object goes in the window, where
  // there is room for it. The menu row already sits under the runner's name.
  #expect(L10n.stop != L10n.serviceStop)
  #expect(L10n.start != L10n.serviceStart)
}

// MARK: - D-R22: one name for the preferences window

@Test func thePreferencesWindowHasOneName() throws {
  // The menu said `Configuración` while the window title — which macOS builds
  // from the app name — said `Ajustes de Standfast`. Two names for the same
  // thing reads as nobody being in charge. The menu row gives way, because the
  // title is the one macOS controls.
  let spanish = try #require(
    L10n.resourceBundle?.path(
      forResource: "Localizable", ofType: "strings", inDirectory: nil,
      forLocalization: "es"))
  let catalogue = try #require(
    NSDictionary(contentsOfFile: spanish) as? [String: String])

  #expect(catalogue["menu.settings"] == "Ajustes")

  // And the strict Accessibility gate looks for that exact row by name, so it
  // has to have been told: a rename here that stops there is a green suite and
  // a red gate.
  let probe = try String(
    contentsOf: URL(fileURLWithPath: #filePath)
      .deletingLastPathComponent().deletingLastPathComponent()
      .deletingLastPathComponent()
      .appendingPathComponent("Scripts/check-app-ax.sh"), encoding: .utf8)
  #expect(probe.contains("\"Ajustes\""))
  #expect(!probe.contains("\"Configuración\""))
}

@Test func theReceiptsUseTheSameVerbAsTheButtonThatCausedThem() {
  // Codex, third pass: "la migración de lenguaje quedó incompleta en F: el
  // error aún dice `solicitud de Parar` y `prueba Parar otra vez`, no `Parar
  // servicio`." Renaming the button and not its receipt leaves the app
  // speaking two dialects about one action.
  #expect(ServiceOperationAction.stop.title == L10n.serviceStop)
  #expect(ServiceOperationAction.start.title == L10n.serviceStart)
  #expect(ServiceOperationAction.restart.title == L10n.serviceRestart)
}

@Test func theConfirmationDialogKeepsItsShortButton() {
  // The dialog is the one place the short verb is still right: its title
  // already names the runner — "¿Parar mac-mini-m4?" — and dialog buttons are
  // short by platform convention.
  let prompt = ServiceActionPrompt(
    action: .stop,
    snapshot: snapshot("build-mac", display: .resolved(.busy)))

  #expect(prompt?.confirm == L10n.stop)
  #expect(prompt?.confirm != L10n.serviceStop)
}

// MARK: - UI-036: a failed order is not hidden by a healthy runner

@Test func aRunnerWhoseLastOrderFailedCountsAsNeedingAttention() {
  // Codex, third pass: "F tiene dos verdades sin jerarquía suficiente. El
  // runner puede seguir listo y, a la vez, haber fallado la orden de pararlo
  // [...] cabecera, icono y píldora verdes dominan, mientras el fallo queda
  // como detalle pequeño."
  //
  // Both facts are true and neither is wrong. What was missing is that the
  // fleet summary — the one line somebody reads first — pretended the second
  // one had not happened.
  let failed = snapshot(
    "build-mac", display: .resolved(.idle),
    operation: ServiceOperation(
      action: .stop, phase: .failed(.scriptMissing),
      changedAt: Date(timeIntervalSince1970: 1_785_962_000)))

  let overview = FleetOverviewPresentation.building(
    snapshots: [failed], notice: nil)

  #expect(overview.attention == L10n.runnerAttention(1))
}

@Test func aRunnerWhoseOrderMerelyTimedOutIsNotCalledAFailure() {
  // `.uncertain` is not `.failed`: a command that timed out may well have
  // worked, and the card already says so. Counting it as attention would make
  // the summary cry wolf on the state this app most often lands in.
  let uncertain = snapshot(
    "build-mac", display: .resolved(.idle),
    operation: ServiceOperation(
      action: .stop, phase: .uncertain(.commandTimedOut),
      changedAt: Date(timeIntervalSince1970: 1_785_962_000)))

  let overview = FleetOverviewPresentation.building(
    snapshots: [uncertain], notice: nil)

  #expect(overview.attention == nil)
}

@Test func aFailedOrderAndABrokenRunnerAreNotCountedTwice() {
  // One runner, two reasons to worry, still one runner.
  let both = snapshot(
    "build-mac", display: .resolved(.disconnected),
    operation: ServiceOperation(
      action: .stop, phase: .failed(.scriptMissing),
      changedAt: Date(timeIntervalSince1970: 1_785_962_000)))

  let overview = FleetOverviewPresentation.building(snapshots: [both], notice: nil)

  #expect(overview.attention == L10n.runnerAttention(1))
}

@Test func aHealthyFleetWithNoFailedOrdersStillSaysNothing() {
  let overview = FleetOverviewPresentation.building(
    snapshots: [snapshot("build-mac", display: .resolved(.idle))], notice: nil)

  #expect(overview.attention == nil)
}
