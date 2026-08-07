import Foundation

/// Runs a blocking call on a thread that is allowed to block, and waits for it
/// without holding one of the runtime's.
///
/// Every blocking entry point in this package needs exactly this hop, and until
/// there was one of these each of them grew its own copy. `svc.sh`,
/// `launchctl` and `gh` are all run through `Process.waitUntilExit()`, which
/// parks the calling thread for up to the command timeout — thirty seconds by
/// default. Swift's cooperative pool has one thread per core and runs *every*
/// `Task`, detached or not, so parking a thread there is parking a share of the
/// whole runtime, the main actor's continuations included.
///
/// A dedicated Foundation thread is used instead of `DispatchQueue.global()`.
/// The global queue normally grows around blocked work, but that is not a
/// guarantee: an older Swift runtime running a large concurrent test suite can
/// exhaust it, leaving both the blocked command and the work that would
/// release it waiting on the same pool. A fresh thread makes the boundary
/// explicit and cannot consume a cooperative executor thread.
///
/// Typed `throws` so the one function serves both kinds of caller. A closure
/// that cannot throw gives `E == Never`, and the call site needs no `try`.
public func offCooperativePool<T: Sendable, E: Error>(
  _ work: @escaping @Sendable () throws(E) -> T
) async throws(E) -> T {
  let outcome: Result<T, E> = await withCheckedContinuation { continuation in
    Thread.detachNewThread {
      autoreleasepool {
        continuation.resume(returning: Result { () throws(E) -> T in try work() })
      }
    }
  }
  return try outcome.get()
}
