# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.2.0] — unreleased

Turns a status light into a progress indicator. Everything new here is read from logs the
runner already writes beside itself, so it stays true to the premise: no API call, no
token, nothing to configure.

### Added

- **The job a runner is building, and how long it has been at it.** `Running testflight —
  1m 20s, usually 2m 50s`, read from the runner's own `_diag` listener log.
- **An estimate that admits when it does not know.** "Usually" is the median of the last
  five *successful* runs of that same job — not the mean, and not every run, because a
  build cancelled after ten seconds would drag a mean down by half a minute and keep it
  there. With fewer than three runs to go on, no estimate is shown at all.
- **The last five jobs**, with how each one ended and how long it took, in a submenu per
  runner. A job whose listener died mid-run is listed as interrupted rather than silently
  dropped.
- **Open at login**, off by default and switched on from the menu. The state shown is the
  registration macOS reports back, not the one that was requested, so a login item waiting
  on the user's approval in System Settings is not drawn as switched on.
- **When the machine was last read.** Stamped when the scan started rather than when it
  landed, so a slow `gh` shows as the stale menu it is.

### Fixed

- **A `svc.sh` killed by the command timeout was treated as an action that had not
  happened**, so the settling window never opened and a start that had gone through was
  reported as `disconnected` — the warning triangle, over a runner that was fine.
- **A scan slower than the refresh interval turned the ticker into a loop.** Every tick
  landing mid-scan left a request pending, so the scan restarted the instant it finished,
  with no pause, for as long as the network stayed slow — spending API calls and battery
  exactly when the machine could least afford it. Ticks are now dropped while a scan is in
  flight, and again while its answer is younger than the interval; an explicit refresh is
  still remembered.

## [0.1.0] — unreleased

First public release. The app previously worked on exactly one machine, with the
repository and runner path written into the source; this release is about making it
installable by anyone.

### Added

- **Zero-configuration discovery.** Every runner installed as a service is found by
  scanning `~/Library/LaunchAgents` and reading each runner's own `.runner` file. No path,
  repository or token to enter.
- **Support for several runners on one Mac**, told apart by where they are registered when
  they share a name, and for runners registered to an **organisation** or to a GitHub
  Enterprise Cloud **account**.
- A distinct reason on every `unknown` state — the GitHub CLI missing, present but not
  authenticated, silent, or launchd unreadable — because each has a different fix.
- English interface with a Spanish translation, English being the default.
- A `Standfast.app` bundle and a Homebrew formula that builds from source, so installing
  never runs into Gatekeeper.

### Fixed

- **Runner status was read from whichever runner the API listed first**, so a second runner
  registered to the same repository silently shadowed the one on screen. Each runner is now
  asked about by its own `agentId`.
- The GitHub CLI was invoked only through `PATH`. An app launched from Finder inherits a
  `PATH` without Homebrew on it, so `gh` was reported as missing on every machine that
  installed it with Homebrew. Standfast now also looks where Homebrew puts it.
- A command writing more than a pipe buffer to `stderr` could hang the app forever.
- The `.runner` file is written with a UTF-8 BOM, which `JSONDecoder` rejects outright.
- Local service state was read by matching text in `svc.sh status` output; it now asks
  launchd directly by the label the LaunchAgent already gave us.

### Changed

- The project is now called **Standfast**. It was `runner-menubar`.
- Split into `RunnerKit`, a UI-free library holding discovery, control, the GitHub client
  and the state machine, and the app target on top of it. All 190 tests run on a machine
  with no runner installed, which is also the only kind of machine CI has.
