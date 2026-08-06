import Combine
import Foundation

/// How hard macOS is currently throttling this Mac.
///
/// This app's own enum rather than `ProcessInfo.ThermalState`, which is a
/// system type that may grow a case: an unrecognised one folded into `.critical`
/// would put the loudest line in the menu over a state nobody has read the
/// meaning of, and folding it into `.nominal` would hide a real one. The two
/// quiet states are one case here because the menu treats them identically —
/// it says nothing at all.
enum ThermalPressure: Equatable {
  /// Nothing to say. `.nominal` and `.fair` both land here: `.fair` means the
  /// fans have come up, which is a Mac working, not a Mac in trouble.
  case none
  /// Throttled enough that work is measurably slower.
  case serious
  /// Throttled as hard as macOS throttles.
  case critical
  /// A state this version does not recognise. Reported rather than guessed at,
  /// and shown as nothing, because a line that cannot say what is wrong is a
  /// line that only worries people.
  case unrecognised
}

extension ThermalPressure {
  init(_ state: ProcessInfo.ThermalState) {
    switch state {
    case .nominal, .fair: self = .none
    case .serious: self = .serious
    case .critical: self = .critical
    @unknown default: self = .unrecognised
    }
  }

  /// Whether this is worth a line in the menu at all.
  ///
  /// Only the two states where the machine is being held back. A menu bar app
  /// that reports "thermal state: nominal" has added a row that is true every
  /// day and useful on none of them.
  var isLimiting: Bool { self == .serious || self == .critical }
}

/// The seam over the machine's own temperature, which a test cannot arrange.
protocol ThermalReporting: Sendable {
  func pressure() -> ThermalPressure
}

struct ProcessThermal: ThermalReporting {
  func pressure() -> ThermalPressure {
    ThermalPressure(ProcessInfo.processInfo.thermalState)
  }
}

/// Watches how hard this Mac is throttling itself.
///
/// Subscribed rather than polled. macOS posts on every change, so there is
/// nothing to add to the fifteen-second scan and nothing to pay for in between
/// — and the reading is a property on `ProcessInfo` rather than a sensor, so
/// the whole feature costs one notification registration.
@MainActor
final class ThermalMonitor: ObservableObject {
  @Published private(set) var pressure: ThermalPressure

  private let reporter: any ThermalReporting
  /// An `AnyCancellable` rather than a `NotificationCenter` token, because it
  /// unsubscribes when this object goes, and a `@MainActor` type's `deinit` may
  /// not touch a token that is not `Sendable`.
  private var subscription: AnyCancellable?

  /// - Parameter center: only a test passes one. The real notification is
  ///   posted by the system on `NotificationCenter.default`, and a test that
  ///   waited for a hot Mac would never finish.
  init(
    reporter: any ThermalReporting = ProcessThermal(),
    center: NotificationCenter = .default
  ) {
    self.reporter = reporter
    pressure = reporter.pressure()
    subscription =
      center
      .publisher(for: ProcessInfo.thermalStateDidChangeNotification)
      // macOS does not promise which thread it posts this on, and this object
      // lives on the main actor. Hopped rather than assumed: assuming wrongly
      // is a crash, not a wrong reading.
      .receive(on: DispatchQueue.main)
      .sink { [weak self] _ in
        MainActor.assumeIsolated {
          guard let self else { return }
          self.pressure = self.reporter.pressure()
        }
      }
  }
}

/// What the menu says about the machine being hot.
enum ThermalNotice {
  /// The lines this puts in the menu, in order, and empty when there is nothing
  /// worth saying.
  ///
  /// - Parameter overrunning: whether some runner's job has already taken
  ///   longer than that job usually takes on this machine. This is the entire
  ///   reason the line is worth a row: a build that normally takes 2m50s and is
  ///   at 6 minutes reads as something broken, and "your Mac is throttled" turns
  ///   it back into something explainable. Crossed with v0.2's estimate rather
  ///   than merely printed next to it — with no job overrunning, the
  ///   temperature is a fact about the hardware and not an answer to anything.
  static func lines(pressure: ThermalPressure, overrunning: Bool) -> [String] {
    guard pressure.isLimiting else { return [] }
    let heat = pressure == .critical ? L10n.thermalCritical : L10n.thermalSerious
    return overrunning ? [heat, L10n.thermalSlowingJobs] : [heat]
  }
}
