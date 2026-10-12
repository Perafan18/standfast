import Foundation
import RunnerKit
import Testing

@testable import Standfast

// Compared against the L10n constants, as in DisplayStateTests: the host may
// speak Spanish, and what is worth pinning is which state reaches which words.

/// Every reason a state can be unknown. `expectedTones(for:)` switches over
/// them with no default, so a new reason fails to compile there: list it here
/// too, and every test below covers it.
private let everyUnknownReason: [UnknownReason] = [
  .cliUnavailable, .notAuthenticated, .noAnswer, .noToken, .rateLimited,
  .gitLabNoToken, .gitLabNotAuthenticated, .gitLabRateLimited, .gitLabSilent,
  .serviceStateUnreadable, .managedFleetWaiting, .managedFleetStatusUnavailable,
  .tokenRefused, .tokenUnreadable, .gitLabTokenUnreadable, .gitLabInsecure,
  .gitLabPaused,
]

private let everyDisplayState: [DisplayState] =
  [
    .resolved(.idle), .resolved(.busy), .resolved(.disconnected), .resolved(.stopped),
    .starting,
  ] + everyUnknownReason.map { .resolved(.unknown($0)) }

private let everyInstallation: [RunnerInstallation] = [
  .launchAgent, .manual, .gitLabService, .managedFleet,
]

private let gitHubScopes: [RunnerScope] = [
  .repository(owner: "acme", name: "widget-factory"), .organization("acme"),
  .enterprise("acme-corp"),
]
private let gitLabScope = RunnerScope.gitLab(
  instance: GitLabInstance(url: "https://gitlab.example.com")!)
private let everyScope = gitHubScopes + [gitLabScope]

private func layers(
  _ display: DisplayState, _ installation: RunnerInstallation = .launchAgent,
  _ scope: RunnerScope = .organization("acme")
) -> RunnerLayersPresentation {
  .building(display: display, installation: installation, scope: scope)
}

private func reading(_ text: String, _ tone: LayerTone) -> LayerReading {
  LayerReading(text: text, tone: tone)
}

/// The owner's split: red only for an offline answer, orange for nobody
/// knowing, a remote that was never asked included, grey for a layer off on
/// purpose.
private func expectedTones(
  for reason: UnknownReason
) -> (local: LayerTone, remote: LayerTone) {
  switch reason {
  case .serviceStateUnreadable, .managedFleetStatusUnavailable: (.unsure, .unsure)
  case .managedFleetWaiting: (.ok, .working)
  case .gitLabPaused: (.ok, .off)
  case .cliUnavailable, .notAuthenticated, .noAnswer, .noToken, .rateLimited,
    .tokenRefused, .tokenUnreadable, .gitLabNoToken, .gitLabNotAuthenticated,
    .gitLabRateLimited, .gitLabSilent, .gitLabTokenUnreadable, .gitLabInsecure:
    (.ok, .unsure)
  }
}

// MARK: - Every combination

@Test func everyStateOnEveryRunnerReadsBothLayers() {
  // A string that came back as its own key is not empty, and still says nothing.
  let prefixes = Set(L10n.english.keys.compactMap { $0.split(separator: ".").first })
  for display in everyDisplayState {
    for installation in everyInstallation {
      for scope in everyScope {
        let subject = layers(display, installation, scope)
        let texts = [
          subject.localName, subject.local.text, subject.remoteName, subject.remote.text,
        ]
        for text in texts {
          #expect(!text.isEmpty, "\(display) \(installation) \(scope)")
          #expect(
            !prefixes.contains { text.hasPrefix($0 + ".") },
            "\(display) \(installation) \(scope): \(text)")
        }
      }
    }
  }
}

@Test func whatEachLayerSaysDependsOnTheStateAlone() {
  // So the state-by-state pins below hold for every runner. Who the layer is
  // belongs to its name.
  for display in everyDisplayState {
    let reference = layers(display)
    for installation in everyInstallation {
      for scope in everyScope {
        let subject = layers(display, installation, scope)
        #expect(subject.local == reference.local, "\(display) \(installation) \(scope)")
        #expect(subject.remote == reference.remote, "\(display) \(installation) \(scope)")
      }
    }
  }
}

@Test func theNamesSayWhoRunsTheRunnerAndWhoHandsItWork() {
  // Distinct, or the checks below could not tell one name from the other.
  #expect(L10n.controlCenterThisMac != L10n.controlCenterFleetSupervisor)
  #expect(L10n.gitHub != L10n.gitLab)

  for display in everyDisplayState {
    for scope in everyScope {
      #expect(layers(display, .launchAgent, scope).localName == L10n.controlCenterThisMac)
      #expect(layers(display, .manual, scope).localName == L10n.controlCenterThisMac)
      #expect(layers(display, .gitLabService, scope).localName == L10n.controlCenterThisMac)
      #expect(
        layers(display, .managedFleet, scope).localName
          == L10n.controlCenterFleetSupervisor)
    }
    for installation in everyInstallation {
      for scope in gitHubScopes {
        #expect(layers(display, installation, scope).remoteName == L10n.gitHub)
      }
      #expect(layers(display, installation, gitLabScope).remoteName == L10n.gitLab)
    }
  }
}

// MARK: - What each state says

@Test func aSettledStateReadsItsOwnWordsOnEachLayer() {
  #expect(layers(.resolved(.idle)).local == reading(L10n.layerLocalRunning, .ok))
  #expect(layers(.resolved(.idle)).remote == reading(L10n.layerRemoteOnline, .ok))
  #expect(layers(.resolved(.busy)).local == reading(L10n.layerLocalRunning, .ok))
  #expect(layers(.resolved(.busy)).remote == reading(L10n.layerRemoteBusy, .working))
  #expect(layers(.resolved(.stopped)).local == reading(L10n.layerLocalNotRunning, .off))
  #expect(
    layers(.resolved(.stopped)).remote == reading(L10n.layerRemoteNotAskedStopped, .off))
  #expect(layers(.starting).local == reading(L10n.layerLocalStarting, .working))
  #expect(layers(.starting).remote == reading(L10n.layerRemoteWaitingToAppear, .working))
}

@Test func disconnectedIsTheMacSayingYesAndTheServiceSayingNo() {
  for installation in everyInstallation {
    for scope in everyScope {
      let subject = layers(.resolved(.disconnected), installation, scope)
      #expect(subject.local == reading(L10n.layerLocalRunning, .ok))
      #expect(subject.remote == reading(L10n.layerRemoteOffline, .no))
    }
  }
}

@Test func onlyAnOfflineAnswerIsDrawnAsANo() {
  // Not answering, rate limited or not asked is nobody knowing, and that
  // runner may be fine. Red there would call it broken.
  for display in everyDisplayState {
    let subject = layers(display)
    #expect(
      (subject.remote.tone == .no) == (display == .resolved(.disconnected)), "\(display)")
    #expect(subject.local.tone != .no, "\(display)")
  }
  for reason in [UnknownReason.noAnswer, .rateLimited, .noToken, .gitLabSilent] {
    #expect(layers(.resolved(.unknown(reason))).remote.tone == .unsure, "\(reason)")
  }
}

@Test func everyUnknownReasonHasTheTonesOfItsLayers() {
  for reason in everyUnknownReason {
    let subject = layers(.resolved(.unknown(reason)))
    #expect(subject.local.tone == expectedTones(for: reason).local, "\(reason)")
    #expect(subject.remote.tone == expectedTones(for: reason).remote, "\(reason)")
  }
}

@Test func aRemoteThatWentQuietStillSaysTheProcessIsRunning() {
  // The local probe goes first, so where it went quiet nobody asked the remote.
  // A fleet slot reads the supervisor's snapshot instead, here stale or with no
  // answer from GitHub. Either way nobody can tell.
  for reason in everyUnknownReason {
    let subject = layers(.resolved(.unknown(reason)))
    if subject.local.tone == .unsure {
      #expect(subject.remote == reading(L10n.layerRemoteNotAsked, .unsure), "\(reason)")
    } else {
      #expect(subject.local == reading(L10n.layerLocalRunning, .ok), "\(reason)")
    }
  }
}

@Test func theLayerAnUnknownIsAboutRepeatsTheBadge() {
  // The sidebar shows `shortSummary`, and the row it opens has to say the same
  // words about the same layer.
  for reason in everyUnknownReason {
    let display = DisplayState.resolved(.unknown(reason))
    let subject = layers(display)
    let quiet = subject.local.tone == .unsure ? subject.local : subject.remote
    #expect(quiet.text == display.shortSummary, "\(reason)")
  }
}
