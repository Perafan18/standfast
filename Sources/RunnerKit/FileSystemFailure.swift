import Foundation

/// Filesystem errors whose meaning is stable across Foundation entry points.
///
/// Directory reads have surfaced both of these Cocoa codes for an absent path
/// across supported macOS versions. Absence is the one read failure callers may
/// turn into an empty listing; every other error means "could not read".
enum FileSystemFailure {
  static func isMissing(_ error: any Error) -> Bool {
    let error = error as NSError
    guard error.domain == NSCocoaErrorDomain else { return false }
    return error.code == CocoaError.Code.fileNoSuchFile.rawValue
      || error.code == CocoaError.Code.fileReadNoSuchFile.rawValue
  }
}
