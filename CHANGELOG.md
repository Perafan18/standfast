# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

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
