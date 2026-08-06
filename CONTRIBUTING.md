# Contributing

Issues and pull requests are welcome. This file covers the conventions the codebase
actually enforces and the traps that have already caught someone once — most of the list
below exists because a change looked obviously correct and was not.

## Getting set up

```sh
make test      # 438 tests, ~1s
make app       # assembles Standfast.app
make run       # assembles and launches it
```

No dependencies, no `.xcodeproj`. Plain SwiftPM. You need Xcode 16 or its command line
tools for a Swift 6 toolchain.

The test suite runs on a machine with **no runner installed** — that is deliberate, since
CI has none. Every external command goes through the `CommandRunning` protocol so it can be
faked. If you find yourself needing a real runner to test something, the seam is in the
wrong place.

The same rule covers everything else the system owns. `UNUserNotificationCenter`,
`ProcessInfo.beginActivity` and `ProcessInfo.thermalState` each sit behind a protocol —
`NotificationDelivering`, `SleepPreventing`, `ThermalReporting` — and every persisted
switch takes its `UserDefaults` as an argument. The suite must never post a banner on the
machine running it, hold a power assertion on it, wait for it to get hot, or depend on a
permission CI cannot grant.

## Conventions

- **Comments explain _why_, not _what_.** Never describe what the next line does, and never
  justify your change to a reviewer — that is what the pull request is for. A comment
  should state a constraint the code cannot show.
- **Swift Testing** (`import Testing`, `@Test`, `#expect`), not XCTest.
- Two-space indentation, lines at most 92 characters, enforced by the versioned
  `.swift-format`. Run it before you push — CI runs the same line and fails on any
  finding:

  ```sh
  swift format lint --strict --recursive Sources Tests   # what CI runs
  swift format --recursive --in-place Sources Tests      # fix it for me
  ```

  `swift format`, with a space: the Command Line Tools ship it as a subcommand of
  `swift`, not as a `swift-format` binary on PATH.
- **The build has zero warnings** and CI fails on any. Keep it that way.
- User-facing strings go through `L10n`, never inline. Add the key to both catalogues and
  to the English fallback table in the same change.
- **A format that mixes `%d` and `%@` must keep them in the same order in every
  catalogue.** `String(format:)` matches specifiers to arguments by position and verifies
  nothing, so a translation that reorders them reads an `Int` through `%@` and dereferences
  it as a pointer — a crash, not a wrong line, and Spanish word order makes the reorder a
  plausible edit. `everyTranslationTakesItsArgumentsInTheSameOrderAndTheSameTypes` compares
  the specifier sequence of every key across catalogues, so this is checked for new keys
  without anyone adding them to a list.

## Writing tests

The bar here is higher than "it passes". Several tests in this repo were rewritten after
review because they could not fail — they re-asserted what a neighbouring test already
covered, or they built their expectation out of the very constant they were testing.

Before you submit, **break your implementation on purpose** and confirm your test dies.
If it survives, the test is decorative. Two real examples from this codebase:

- A test pinned the `gh` argument list by building it from `statusFilter` itself, so the
  filter's contents were never actually checked. It now pins the literal, with a comment
  saying it must not use the constant.
- The assertion for "discovery does not block the wrong thread pool" only checked it was
  off the main thread — which was already true and was the wrong condition. It missed the
  bug entirely.

## Traps

Each of these looks like a cleanup and is a regression.

**Do not enable App Sandbox.** Under sandbox,
`FileManager.default.homeDirectoryForCurrentUser` returns the app's container rather than
`~`, and `~/Library/LaunchAgents` becomes unreachable. Discovery — the whole point of the
app — stops working *silently*: an empty menu, no error, because as far as the app can
tell this Mac simply has no runners. There is no entitlement that buys the directory
back either; LaunchAgents is not one of the user-selected or well-known locations a
sandboxed app may reach. The same reasoning is in `Resources/Info.plist`, next to the
key that would have to be added.

**Do not send `stderr` to a `Pipe()`** in `ProcessCommandRunner`. A pipe nobody drains
blocks the child forever once it writes more than the buffer holds, which a `gh` with a
long error message will. It goes to the null device on purpose, and
`survivesAProcessThatIsChattyOnStderr` is there to catch the revert.

**Do not reach for `Bundle.module`.** Its generated accessor calls `fatalError` when it
cannot find its bundle, which is exactly the situation inside a hand-assembled `.app` on
somebody else's machine. It crashed on launch for every user once already. `L10n` searches
for the bundle itself and treats "not found" as an ordinary answer.

**Never gate a per-runner action on the aggregate state.** With one runner idle and another
stopped, the fleet summary is `idle` — correct by design — and a Start button gated on the
summary leaves the stopped runner impossible to start. Every action reads its own runner's
state.

**Blocking entry points are named `blocking*`.** `blockingState`, `blockingStart`,
`blockingStop`, `blockingIsRunning`, `blockingRunnerStatus`. They occupy a whole thread
inside `waitUntilExit()`, twice per call, up to the command timeout. Do not call them
from the UI: use the `async` facades, which hop to `DispatchQueue.global()`. `Task {}` and
`Task.detached {}` both land on the cooperative pool, whose width is the core count, so
"off the main actor" is not enough.

**Do not drop the `codesign` line at the end of `Scripts/build-app.sh`.** It is ad-hoc
and it looks like something only a release needs. It is not: SwiftPM leaves the executable
linker-signed with the identifier `Standfast` and `Info.plist` unbound, so an unsigned
bundle has no bundle identity as far as the system is concerned. `usernoted` then declines
to register `dev.standfast.app` and drops every notification the app posts — no banner, no
error, nothing in any log. `check-app.sh` compares the identifier `codesign` reports
against the one `Info.plist` claims, which is the only way this failure is visible from
outside.

**The `.runner` file starts with a UTF-8 BOM.** `JSONDecoder` rejects it. The fixture
carries real BOM bytes so a regression fails the test rather than only failing on somebody's
machine.

**Do not lower the `_diag` sweep's listener-log floor.** `DiagnosticsRetention.standard`
keeps `JobLogReader.retainedListenerLogs` of them, and that is `maxFiles + 1`. The `+ 1`
looks like an off-by-one somebody left in and it is the opposite: `coldStart` reads the
active log *and then* walks `maxFiles` further files back, so the reach is `maxFiles + 1`
files and a floor of `maxFiles` deletes the one the walk ends on. What that costs is the
menu's job history going short the next time the listener rotates — no crash, no error, five
rows quietly becoming two — and the sweep is the last place anybody would look for the
reason. It is also not an exotic case: on a laptop every sleep and wake rotates a log
without running a single job, so twenty-five rotations go by long before twenty jobs do.
`aRotationTheReaderCanStillWalkBackThroughKeepsItsJobs` reads a real `_diag` on both sides
of a sweep and is there to catch the revert.

**Nothing destructive may be tested against a path a person owns.** Every test that deletes
points at a `RunnerDirectorySandbox` or a `HousekeepingSandbox` under
`NSTemporaryDirectory()`, and the deletion itself sits behind `DestructiveFileOperations` so
that a *refusal* can be asserted as "nothing was called". "The directory is still there" is
satisfied by a delete that failed as well as by one that never ran, and only one of those is
the code working. The suite runs on machines with a real runner on them, and the difference
between the two is one wrong string.

## Packaging changes

If you touch `Scripts/build-app.sh` or `Resources/Info.plist`, run the packaging check:

```sh
make check          # swift test, then the script below
./Scripts/check-app.sh
```

It assembles the bundle, **deletes `.build`**, launches the app and confirms it is still
alive. That deletion is the point — with the build directory present, a broken bundle still
resolves and the failure hides. No unit test can catch this class of bug.

## Releasing

The version is written in two places that no build step keeps in step:
`CFBundleShortVersionString` in `Resources/Info.plist`, and the tag inside `url` in
`Formula/standfast.rb`. CI compares them and fails when they disagree, which is the only
thing standing between a bump and an app that reports last release's version forever.

So a release is, in order:

1. Bump `CFBundleShortVersionString` and the formula's `url` tag together, in one commit.
2. In `CHANGELOG.md`, replace `— unreleased` on that version's heading with the date,
   and open a new heading above it.
3. Tag `v<version>` and push the tag.
4. Put the release tarball's `sha256` into the formula, replacing `REPLACE_ON_RELEASE`,
   and copy the formula into the tap.

`CFBundleVersion` is the build number and is deliberately not tied to any of this.
