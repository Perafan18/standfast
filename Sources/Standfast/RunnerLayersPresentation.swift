import Foundation

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
