# Changelog

All notable changes to this project are documented here. The format follows
[Keep a Changelog](https://keepachangelog.com/en/1.1.0/), and versions follow
[Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.5.0] — 2026-10-09

The first public release, published as source: `brew install perafan18/tap/standfast`
builds it on your Mac. A signed and notarized download is not available yet; it needs a
Developer ID certificate.

### Added

- **Honest, per-runner service-operation outcomes.** Start, Stop, and Restart now report
  their in-flight, request-accepted, uncertain, or failed outcome under the runner that was
  acted on. A returned `svc.sh` command is never presented as proof of the next runner
  state, a timeout admits the result is uncertain, and Restart distinguishes a completed
  Stop from a failed or timed-out Start phase. In-flight feedback remains until completion;
  each terminal receipt uses a nominal five-minute scan-wall-clock window and is pruned by
  the next normal scan. A system clock correction can shorten or extend the displayed
  interval; this presentation receipt is deliberately timer-free rather than an exact
  elapsed-time guarantee.
- **A singleton Standfast Control Center** with one scrolling column of native runner
  cards. Each card keeps the complete operational picture together: local and GitHub state,
  current work, service controls, the latest operation outcome, recent jobs, runner version,
  manual disk measurement and safe cleanup, logs, and the appropriate GitHub destination.
- **A slim quick menu** for a three-second glance. It shows one row per runner, in
  discovery order, each opening a submenu with that runner's state, progress, current
  managed job and latest operation receipt; discovery and thermal alerts; freshness;
  Refresh; Open Standfast; Settings; and Quit. A conclusively stopped runner may offer
  Start; Stop, Restart, history, maintenance, preferences, and confirmations stay out of
  the quick surface.
- **A separate Settings scene** for notification choices, SleepGuard, Open at Login, the
  optional Dock tile, the GitHub and GitLab tokens, and the folders of runners started by
  hand, using the same long-lived preference state as the rest of the app.
- **Accessibility semantics for the new surfaces.** The menu-bar item exposes the product
  name and aggregate state, runner cards and operation feedback expose names and values,
  decorative duplicate text is hidden from assistive technology, and native controls keep
  keyboard order and focus. State is never conveyed by color or motion alone, and the
  only two animations — a card folding and a receipt appearing — become an immediate
  change under Reduce Motion.
- **An original Standfast app icon:** a text-free sentinel/beacon, compiled into every macOS
  icon size and included inside the signed resource seal. Live status remains the job of
  semantic SF Symbols in the menu bar rather than the product icon.
- **A GitHub client of Standfast's own,** with the token in the Keychain. `gh` is now a
  fallback used only when nothing is stored, so a menu bar app no longer requires a
  terminal tool to be installed, authenticated and well-behaved before it can say anything
  about a runner. Every query carries the previous `Etag`, so an unchanged answer costs a
  304 that GitHub does not bill — measured against `x-ratelimit-remaining`, not assumed.
  Settings says whether a token exists and never what it is.
- **Queued work, by label.** The app answers the question that names it — not "are you
  ready" but "is there work waiting for *this* runner" — reproducing GitHub's dispatch rule
  that a job goes to a runner carrying every label it asked for. A stopped runner, whose
  labels the app does not know, is left unanswered rather than declared idle. Organization
  and enterprise runners say the question cannot be answered there, because GitHub has no
  endpoint for it.
- **Runners started by hand.** A runner launched with `./run.sh` leaves no LaunchAgent and
  was invisible to a product that promises to find your runners. Their folders are pointed
  at explicitly in Settings — never guessed by walking the disk — re-read on every scan,
  and probed by process rather than by launchd. Service controls stay off for them, with
  the reason beside them.
- **GitLab runners, beside the GitHub ones,** scoped to what the product already promises:
  whether the runners on this machine will get work. Discovery reads the fixed, documented
  `~/.gitlab-runner/config.toml`; the runner token stays in that file, and self-managed
  GitLab works because the instance address — scheme, host, port and path — travels from
  each runner's config. Each instance has its own token in Settings, sent only to that
  instance and only over https. GitLab states are phrased in GitLab's own words, since
  "run gh auth login" is the wrong advice for a GitLab token.
- **An optional Dock tile.** Standfast lives in the menu bar and still starts without one;
  a switch in Settings promotes it at launch for anybody who wants it in the Dock and in
  ⌘-Tab.
- **`Scripts/install-app.sh`,** which installs over the running copy, keeps the version you
  were running and the one before it, and cannot take away the only working app if the
  build fails.

### Changed

- Repository runners now open that repository's workflow-runs page. Organization and
  enterprise runners instead open their honest runner-settings page; Standfast no longer
  labels those registration destinations as run history.
- The operational interface uses native `GroupBox`, `LabeledContent`, `ControlGroup`,
  `Form`, and system semantic styles, with no custom color or type scale in the app UI.
- The app names its state layers when they disagree — local and remote no longer collapse
  into one word — the service verbs name their object (`Parar servicio`, not `Parar`), the
  idle state is called `Listo` in both the short and long forms, and the preferences window
  has one name instead of two.
- Job rows say when before they say how long, in words: `hace 6d · duró 43s`. A bare
  duration in parentheses read as an age, and two bare numbers side by side left the reader
  guessing which was which.
- The empty Control Center no longer repeats the header it sits under. It spends that room
  on what to install and on where a runner already started by hand goes.
- CI runs entirely on the self-hosted Mac. No rented macOS minutes, and `Build and test`
  dropped from ~2 min to 43 s. The trade is stated in the docs: the job that compiled
  against an older Xcode on a real macOS 14 is gone.

### Fixed

- Review follow-ups keep runner progress, operation feedback, and Start inside one runner
  submenu so detail cannot silently exceed the quick menu's top-level row budget.
- The packaging/AX audit now checks a singleton main and focused Control Center, bounds its
  Settings close attempts, verifies every required icon representation, and confirms the
  opaque 1024×1024 source and sealed `.icns` rather than checking only that an icon exists.
- The local app check now requires readable menu and window Accessibility evidence by
  default. CI opts explicitly into a packaging smoke mode whose output states that menu,
  windows, and Accessibility are not covered.
- Every Settings row now spans its card, so the switches share one trailing edge instead of
  each row hugging its own label and leaving the notification section ragged.
- The Accessibility lifecycle probe drives the status menu with real pointer events and
  proves the menu is open from its on-screen geometry. On macOS 27 `AXPress` marks a
  `MenuBarExtra` item as pressed without running its action, and `AXSelected` then reports
  success for a press that opened nothing — so the probe failed against a working app and
  blamed a screen lock that was not there. A locked screen is now reported as a diagnosis
  attached to whatever the probe actually observed, never as the verdict itself.
- A second job failing inside the same second as the first was never announced. A timestamp
  was doing the work of an identity; the watermark now carries the instant *and* how many
  finished records shared it.
- A runner with no version reported is told apart from a log that cannot be read, instead
  of both arriving as one empty optional.
- The local probe's read timestamp was an upper bound being used as causal evidence by the
  settling window. A reading now carries both ends.
- A rotated log repaired after an unreadable read reappears in about ten minutes, instead of
  waiting for the next rotation. Stopping on budget is a correct ending and is not retried.
- A busy runner whose configuration stops resolving keeps its evidence — the job is probably
  still running — but no longer without bound: half an hour, ten times the longest job this
  machine has run.
- A checkout symlinked outside the runner folder erased the whole row. Discovery yields the
  runner; only maintenance abstains, and it says why.
- The strict Accessibility gate blamed a locked screen for a failure caused by a second
  copy of the app running, and its diagnosis note lived inside a branch that did not exist
  when the menu bar was visible.
- The four places that promise a minimum macOS — `Package.swift`, `Info.plist`, the README
  and the landing page — are held equal by a contract. Bumping one used to leave the others
  promising a version macOS would still install on a system where the app cannot run.

Fixed in the pre-launch review, before anything was published:

- **Building and releasing.** `make app` and the release failed on a clean checkout with
  Xcode 27, whose Swift Build backend nests the localisation catalogues one level deeper in
  the resource bundle. The Homebrew formula could not build inside Homebrew's own sandbox,
  and could not build with the Command Line Tools alone, which lack SwiftUI's macro plugin;
  it now asks for Xcode. The release is universal, so Intel Macs can open the download; a
  tag that does not match the app's version is refused; `make check` passes on a Mac that
  holds a Developer ID certificate; and the Homebrew caveat copies the app into
  /Applications instead of linking it, which Spotlight ignores.
- **CI on a public repository.** The jobs on the self-hosted Mac skip a fork's pull request
  that leaves the workflows untouched, and the workflow token is read-only. A fork brings its
  own copy of the workflow and can remove that guard, so the control is the repository
  setting that requires approval for every outside contributor; CONTRIBUTING says so.
- **GitHub reasons that send you to the right fix.** A token GitHub refuses says to replace
  the token, not to run `gh auth login`; no token and no `gh` says to add a token; a
  Keychain that will not hand the token over, and a secondary rate limit, each say what
  they are. A request that trickles bytes is bounded at 30 seconds in total, and a queue
  count capped by GitHub says it is partial.
- **Keychain reads never freeze the app.** Tokens are read off the main thread, one read per
  item at a time, so a locked Keychain or an upgraded build asking for access raises one
  dialog instead of one per runner, and a refusal is not asked again every refresh. `gh`
  installed through MacPorts, nix, mise or asdf is found when Standfast is opened from
  Finder or at login.
- **GitLab.** Each instance keeps its own token, sent only to that instance, only over
  https, and never along a redirect to another origin. Instances on another port, under a
  path or at an IPv6 address are asked where they are, instead of crashing the Control
  Center or asking the wrong server. A runner paused in GitLab reads as paused and is not
  announced as disconnected; the card of an instance served over http says it is not
  asked and offers no token field, keeping Remove; a hand-edited
  `config.toml` with CRLF, a BOM or commented-out sections keeps its runners; same-named
  runners on one instance are two cards; a GitLab runner GitLab cannot see says GitLab,
  links to GitLab, offers no disk measurement of folders it never uses, and Settings
  offers a token card for a gitlab-runner registered after launch.
- **Runners started by hand.** They are found in folders with accented names, under /tmp
  or /var, or behind a symlink; they no longer read as stopped, or announce a crash, while
  they update or restart themselves; Standfast looks for them among your own processes
  only, so another account's process never makes it touch a remote path; and the menu no
  longer offers Start for runners Standfast cannot start.
- **Job history.** A job left without a result stops counting as running, and stops
  keeping the Mac awake. A job that spans the listener's log rollover keeps its result and
  its failure notification, the runner version survives the rollover, a runner started by
  hand that stops mid-job shows that job as interrupted, and a managed-fleet job from a
  `.github` repository keeps its links.
- **Discovery and maintenance.** A runner whose work folder is configured outside its
  directory is watched again, with maintenance abstaining. Pool slots are listed in
  numeric order. A symlinked tool or action cache is left in place rather than deleted,
  and a `.github` checkout counts as a checkout.
- **Notifications.** "Disconnected" is announced once the disconnection has lasted 30
  seconds, so a runner still registering at login, after a wake or after a restart is not
  a false alarm, and that wait starts again after a sleep or a clock step; an unreadable reading no longer makes the next real one look new; two
  runners with the same name get their own banners; and the permission notice is re-read
  whenever Settings is shown.
- **The model and its surfaces.** Automatic refresh survives a clock set backwards. A
  maintenance refusal says why it refused instead of always blaming new work, and its
  notices clear on Measure or Cancel. A capped queue with no matches no longer claims
  nothing is waiting. The prominent buttons stay legible in a window that is not in front,
  turning the Dock tile off keeps Settings in front, Open at Login reflects changes made in
  System Settings, and the login-items pane is named as macOS 15 names it.
- **Copy.** Enterprise runners are named when GitHub cannot show their queue, and several
  Spanish lines were corrected: "1 o más trabajos", consistent gender for "Mac", and
  sentences that had lost their subject.

No Standfast version has been published yet. The 0.1.0 through 0.4.0 sections below are
integrated development milestones that were built and reviewed in sequence, never tags or
public releases. They remain separate because each records a distinct stage of the current
unreleased source tree.

## [0.4.0] — development milestone, integrated into 0.5.0

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
  hundred thousand files; 0.16 s warm on the 4.5 GB above (0.24 s for the whole reading,
  plan included), and seconds on a Mac that has just woken. No timer and no staleness rule
  either — the number is taken when somebody
  asks for it, and the line under it says how old it is, which is what makes reading on
  demand honest rather than lazy.
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
  the listener has open is never deleted, and neither are the newest 25 listener logs —
  that number is `JobLogReader`'s own reach and not a second opinion about it: the reader
  walks the active log plus 24 rotations behind it, so a floor of 24 would take the file
  its walk ends on. On a laptop that is ordinary rather than exotic, because every sleep
  and wake rotates a log without running a single job. A sweep therefore cannot quietly
  shorten the job history the Control Center shows.
- **The runner's own version**, read out of the header its listener writes, with the newest
  published `actions/runner` release beside it when there is a newer one. GitHub is asked at
  most once a day, and a check that got no answer still counts as having asked.

### Fixed

- **"Open on GitHub" reached `NSWorkspace` directly**, so every run of the test suite threw
  a browser tab at a fixture repository on whoever's machine was running it. The test that
  covered it asserted only that no command had been spawned — and opening a URL spawns
  none, so nothing ever failed. The opener now goes behind a seam like the notification
  centre and the power assertion, and the test pins the URL.

## [0.3.0] — development milestone, integrated into 0.5.0

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

## [0.2.0] — development milestone, integrated into 0.5.0

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

## [0.1.0] — development milestone, integrated into 0.5.0

Initial installable development milestone. The app previously worked on exactly one
machine, with the repository and runner path written into the source; this milestone made
the source build reusable without claiming a published distribution.

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
- A `Standfast.app` bundle and draft Homebrew formula for a future source distribution.

### Fixed

- **Runner status was read from whichever runner the API listed first**, so a second runner
  registered to the same repository silently shadowed the one on screen. Each runner is now
  asked about by its own `agentId`.
- The GitHub CLI was invoked only through `PATH`. An app launched from Finder inherits a
  `PATH` without Homebrew on it, so `gh` was reported as missing whenever Homebrew installed
  it. Standfast now also looks where Homebrew puts it.
- A command writing more than a pipe buffer to `stderr` could hang the app forever.
- The `.runner` file is written with a UTF-8 BOM, which `JSONDecoder` rejects outright.
- Local service state was read by matching text in `svc.sh status` output; it now asks
  launchd directly by the label the LaunchAgent already gave us.

### Changed

- The project is now called **Standfast**. It was `runner-menubar`.
- Split into `RunnerKit`, a UI-free library holding discovery, control, the GitHub client
  and the state machine, and the app target on top of it. All 190 tests run on a machine
  with no runner installed, which is also the only kind of machine CI has.
