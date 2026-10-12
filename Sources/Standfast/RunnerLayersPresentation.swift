import Foundation
import RunnerKit

/// How one of a runner's two layers reads: the process on this Mac, or the
/// service that hands it work. Not a `StateTone`, because "GitHub says
/// offline" is a no and "GitHub did not answer" is nobody knowing.
enum LayerTone: Equatable, Sendable {
  case ok
  /// Starting, or running a job.
  case working
  /// A definite answer that the layer is down.
  case no
  /// Nobody could tell. The runner may be fine, so never drawn like `no`.
  case unsure
  /// Off on purpose, or not asked because the answer could not matter.
  case off
}

/// One layer's answer. The text says it on its own; the tone only colours it.
struct LayerReading: Equatable, Sendable {
  let text: String
  let tone: LayerTone
}

/// Is the process alive here, and will GitHub or GitLab give it work: asked
/// apart, because a runner with an expired token keeps running while GitHub
/// writes it off. The readings follow the state; the names, who runs it.
struct RunnerLayersPresentation: Equatable, Sendable {
  let localName: String
  let local: LayerReading
  let remoteName: String
  let remote: LayerReading

  static func building(
    display: DisplayState, installation: RunnerInstallation, scope: RunnerScope
  ) -> Self {
    let (local, remote) = readings(of: display)
    let remoteName: String
    if case .gitLab = scope {
      remoteName = L10n.gitLab
    } else {
      remoteName = L10n.gitHub
    }
    return Self(
      localName: installation == .managedFleet
        ? L10n.controlCenterFleetSupervisor : L10n.controlCenterThisMac,
      local: local, remoteName: remoteName, remote: remote)
  }

  /// Both readings, each after its layer's name. Where the two sit in columns
  /// the position names the layer, and VoiceOver hears no position.
  var accessibilityValue: String {
    L10n.controlCenterLayersValue(localName, local.text, remoteName, remote.text)
  }

  private static let running = LayerReading(text: L10n.layerLocalRunning, tone: .ok)

  private static func readings(of display: DisplayState) -> (LayerReading, LayerReading) {
    switch display {
    case .resolved(.idle):
      (running, LayerReading(text: L10n.layerRemoteOnline, tone: .ok))
    case .resolved(.busy):
      (running, LayerReading(text: L10n.layerRemoteBusy, tone: .working))
    // The one remote answer that is a no. Every failure below is nobody
    // knowing, and red there would call a runner that may be fine broken.
    case .resolved(.disconnected):
      (running, LayerReading(text: L10n.layerRemoteOffline, tone: .no))
    // The resolver settles a stopped service without asking: no answer could
    // change it.
    case .resolved(.stopped):
      (
        LayerReading(text: L10n.layerLocalNotRunning, tone: .off),
        LayerReading(text: L10n.layerRemoteNotAskedStopped, tone: .off)
      )
    case .starting:
      (
        LayerReading(text: L10n.layerLocalStarting, tone: .working),
        LayerReading(text: L10n.layerRemoteWaitingToAppear, tone: .working)
      )
    case .resolved(.unknown(let reason)):
      readings(of: reason)
    }
  }

  /// The words the short state already uses, on the layer they are about.
  /// GitHub and GitLab are asked only after the local probe said yes, so a
  /// remote that went quiet still means the process is running.
  private static func readings(of reason: UnknownReason) -> (LayerReading, LayerReading) {
    // Where the local half went quiet the remote was never asked, and not
    // because its answer could not matter: nobody can tell whether it would
    // hand this runner work. So orange, where a stopped service's is grey.
    let notAsked = unsure(L10n.layerRemoteNotAsked)
    switch reason {
    case .serviceStateUnreadable:
      return (LayerReading(text: L10n.stateLayerLocalUnreadable, tone: .unsure), notAsked)
    // A fleet slot is read from the supervisor's snapshot, never from GitHub.
    // This is that snapshot gone stale or carrying no answer from GitHub, which
    // RunnerKit does not tell apart.
    case .managedFleetStatusUnavailable:
      return (
        LayerReading(text: L10n.stateLayerManagedFleetUnavailable, tone: .unsure), notAsked
      )
    // The supervisor is preparing the slot's next runner: work under way.
    case .managedFleetWaiting:
      return (
        running, LayerReading(text: L10n.stateLayerManagedFleetWaiting, tone: .working)
      )
    // An answer, and a pause is how somebody drains a runner on purpose.
    case .gitLabPaused:
      return (running, LayerReading(text: L10n.stateLayerGitLabPaused, tone: .off))
    case .cliUnavailable, .notAuthenticated, .noAnswer:
      return (running, unsure(L10n.stateLayerGitHubSilent))
    case .noToken, .tokenUnreadable:
      return (running, unsure(L10n.stateLayerGitHubNotAsked))
    case .tokenRefused:
      return (running, unsure(L10n.stateLayerGitHubRefusedToken))
    case .rateLimited:
      return (running, unsure(L10n.stateLayerGitHubRateLimited))
    case .gitLabNoToken, .gitLabTokenUnreadable, .gitLabInsecure:
      return (running, unsure(L10n.stateLayerGitLabNotAsked))
    case .gitLabNotAuthenticated:
      return (running, unsure(L10n.stateLayerGitLabRefusedToken))
    case .gitLabRateLimited:
      return (running, unsure(L10n.stateLayerGitLabRateLimited))
    case .gitLabSilent:
      return (running, unsure(L10n.stateLayerGitLabSilent))
    }
  }

  private static func unsure(_ text: String) -> LayerReading {
    LayerReading(text: text, tone: .unsure)
  }
}
