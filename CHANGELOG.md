# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [0.4.0] — unreleased

Stops the runner quietly eating the disk. Measured on one real runner: `_work` was 4.5 GB,
of which the hosted tool cache alone was 4.33 GB — 91% of it, and a cache — while `_diag`
was 9 MB and growing by about ten a day with no rotation whatsoever, which is three and a
half gigabytes a year of text nobody will ever read.

### Added

- **A per-runner Maintenance submenu** showing what `_work` and `_diag` actually cost,
  broken down by what each directory is *for*: the tool cache, the actions the runner
  downloaded, the repository checkouts, and the logs. The breakdown is the point — a total
  is something to be alarmed by, a cache is something to press a button about.
- **Measured on demand and never on the refresh loop.** `du -sk` in a child process rather
  than a Foundation enumerator, because that is what the system optimises for a couple of
  hundred thousand files; it took 0.54 s on the 4.5 GB above, which is far too long to
  spend every fifteen seconds and nothing at all to spend when somebody asks. The submenu
  says how old its numbers are.
- **Freeing the two caches, and only those two.** `_work/_tool` and `_work/_actions` are
  re-fetched on a miss, so losing either costs one slow build and nothing else. The
  repository checkouts are never offered: nothing in one is a cache, a workflow that wrote
  a file git does not track loses it, and they were 9% of `_work` here. Neither is
  `_work/_temp`, which reads as the safest of the lot and is the most dangerous — it is
  `$RUNNER_TEMP`, holding the scripts of a job in flight, and it is empty whenever the
  runner is idle.
- **Deleting is offered only while the runner is idle or stopped**, read off that runner
  and never off the fleet summary, and the state is checked again immediately before
  anything goes. `.disconnected` does not count: GitHub reports a Mac that dropped mid-job
  as offline with the job still assigned to it.
- **The deletion itself is a rename.** The directory is moved aside in one atomic syscall
  and taken apart afterwards, so the window between the last check and the point of no
  return is a single `rename(2)`. A job that starts a microsecond later finds no tool cache
  — a cache miss and a slower build — rather than half a tool cache, which is a broken
  toolchain and a failed build.
- **A confirmation that names the directory, the size and the runner**, and says what
  losing it costs. Return cancels rather than confirms.
- **Rotating `_diag`**, keeping everything written in the last week. Almost all of it is
  worker logs, which are half a megabyte each and which nothing in this app reads. The log
  the listener has open is never deleted, and neither are the newest 24 listener logs —
  that number is `JobLogReader`'s own reach, not a second opinion about it, so a sweep
  cannot quietly shorten the job history the menu shows.
- **The runner's own version**, read out of the header its listener writes, with the newest
  published release beside it when there is a newer one. GitHub is asked at most once a
  day, and a check that got no answer still counts as having asked.

## [0.3.0] — unreleased

Makes the app worth having when nobody is looking at it. Everything here is off until
switched on, and the whole design question was not how to notify but what is worth
notifying about: measured over two days on one real runner, 17 jobs produced 14
`Succeeded`, 2 `Canceled` and 1 `Failed`, so a banner per job would be eight interruptions
a day of which one in six carries information.

### Added

- **Notifications for the three things you cannot find out by looking**: a job that
  failed, a runner GitHub can no longer see, and a runner that stopped without being
  asked to. Each has its own switch, all of them off on a fresh install. Successful and
  cancelled jobs are deliberately silent.
- **A stop you ordered is never reported back to you.** Stop and Restart tell the watcher
  a stop is coming, which is the only evidence there is: `launchctl` cannot say who
  brought a service down.
- **Nothing is announced from history.** `_diag` reaches back about two days, so a runner
  is baselined the first time it is seen and only what changes afterwards is reported —
  otherwise every login would replay a build that broke on Tuesday.
- **The permission prompt is deferred to the moment a switch goes on**, never asked for at
  launch. macOS offers it once, and a no given before the app has shown why is a no that
  applies forever after.
- **Keeping the Mac awake while a job runs**, off by default, held through
  `ProcessInfo.beginActivity` rather than a `caffeinate` subprocess — an assertion this
  process holds dies with it, where a child outlives a crash and leaves a Mac that will
  not sleep. One assertion for the whole machine, so one runner finishing does not let the
  Mac sleep out from under another. The menu says what it cannot do: closing the lid still
  sleeps the Mac.
- **A thermal line, and only when macOS is actually throttling.** `.serious` and
  `.critical` get a row; nothing else does. When a job has also overrun the estimate v0.2
  computes, a second line says so — which is the only situation where the temperature
  answers a question somebody has.

### Fixed

- **The assembled app had no bundle identity**, so every notification it posted was
  dropped without a trace. SwiftPM leaves the executable linker-signed as `Standfast` with
  `Info.plist` unbound, and `usernoted` never registered `dev.standfast.app` at all. The
  bundle is now ad-hoc signed at the end of `build-app.sh`, and the packaging check fails
  if the signed identifier is not the one `Info.plist` claims.

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
