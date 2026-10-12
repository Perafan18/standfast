import AppKit
import Foundation

/// Handing a URL to the user's browser is a side effect on their session, not
/// on this app, and it is the one such effect that had no seam: a test that
/// reached the real opener took over the machine running the suite, piling up
/// browser tabs pointed at a fixture repository. Injected for exactly the same
/// reason as the notification centre and the power assertion.
protocol URLOpening: Sendable {
  func open(_ url: URL)
}

struct WorkspaceURLOpener: URLOpening {
  func open(_ url: URL) { NSWorkspace.shared.open(url) }
}

/// Selecting a folder in Finder brings Finder forward over whatever somebody
/// was doing: the same kind of effect as opening a URL, and kept out of the
/// suite for the same reason.
protocol FileRevealing: Sendable {
  func reveal(_ url: URL)
}

struct WorkspaceFileRevealer: FileRevealing {
  func reveal(_ url: URL) { NSWorkspace.shared.activateFileViewerSelecting([url]) }
}
