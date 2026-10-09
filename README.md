# Standfast

**A macOS menu bar app for self-hosted GitHub Actions runners.** Its status item tells you,
without a click, whether your runners are actually going to get work. A slim quick menu
keeps the fleet glanceable; the Standfast Control Center holds the complete operational
picture and controls.

<!-- TODO before launch: a GIF of the menu bar cycling idle → busy → disconnected.
     Nothing sells this app like watching the icon change while the machine stays up. -->

## Why it exists

A runner whose registration has lapsed keeps its process happily running. `svc.sh status`
still prints `Started`. Activity Monitor still shows it. The machine is fine. The next job
simply never arrives, and you find out when someone asks why the build has been queued for
an hour.

So Standfast asks two questions instead of one, and never collapses them:

- **launchd** answers whether the process is alive.
- **The GitHub API** answers whether GitHub still counts on it.

Only the second one decides whether your build runs. That is why a runner that is up but
unreachable gets a state of its own instead of being filed under "stopped" — the symptom
looks similar and the fix is not.

## What the menu-bar status icon means

| Icon | State | Meaning |
|---|---|---|
| ✓ | `idle` | Registered, connected, waiting for work. The one you want to see. |
| ⚙ | `busy` | Running a job right now. |
| ⚠ | `disconnected` | The process is alive, but GitHub cannot see it. No job is coming. |
| ☾ | `stopped` | The service is not running. Start it from the quick menu or Control Center. |
| ? | `unknown` | Standfast could not tell — and says which of the reasons it was. |
| ↻ | `starting` | You just started it; GitHub has not acknowledged it yet. Held for 30s. |
| ◌ | — | This Mac has no runners at all. Not a failure to read one. |

`unknown` is never a shrug. It says which of the reasons it was — no token in Settings and
no GitHub CLI either, a credential GitHub refused, a rate limit, an answer with nothing
usable in it, *launchd could not be asked*, and their GitLab and managed-fleet
counterparts — because each one has a different fix.

## Quick menu, Control Center and Settings

The quick menu is deliberately small. It shows one row per runner, in discovery order, each
opening a submenu with that runner's state, progress, current managed job and latest
operation receipt; any compact discovery or thermal warning; when Standfast last looked;
and four fixed actions: Refresh, Open Standfast, Settings, and Quit. A conclusively stopped
runner may offer Start inside its submenu. Stop, Restart, history, maintenance, preferences
and confirmations do not live there.

**Open Standfast** brings forward one persistent, single-column Control Center. Each runner
gets a card with its local and GitHub state, current job, Start/Stop/Restart controls, the
latest operation outcome, recent history, installed version, manual disk measurement and
safe cleanup, logs, and its GitHub destination. Repository runners open the repository's
workflow-runs page; organization and enterprise runners open their runner-settings page,
which is the honest shared-scope destination GitHub provides.

Service operations keep their own receipts per runner. In-flight work is visible
immediately and remains visible for as long as the command is running. After an operation
reaches an accepted, uncertain, or failed outcome, its terminal receipt remains for a nominal
five-minute scan-wall-clock window and is pruned by the next normal scan at or after that wall-clock
boundary. A system clock correction can shorten or extend the displayed interval. After that
nominal window, any terminal receipt—including a failure—can expire before you see it; the
runner's current state remains, but that operation explanation is no longer displayed. A
command that returned is described as *request accepted*, not as a state the next probe has
not proved. Timeouts say the result is uncertain, and Restart says when Stop completed but
the Start phase failed or timed out so the recovery step is clear.

**Settings** owns the notification switches, the folders of runners started by hand, the
optional GitHub token, an optional token for each GitLab instance gitlab-runner's
`config.toml` names, SleepGuard, Open at Login, and whether Standfast also takes a Dock tile.
Those preferences share their existing state with the app; moving the controls did not
create a second copy.

## Accessibility and app identity

The status item exposes both the Standfast label and the aggregate fleet value to assistive
technology. Control Center cards and operation feedback expose names, roles and values;
native controls preserve keyboard order and visible focus, and text accompanies every
meaningful symbol. No state depends on color or motion alone. The only two animations —
a card folding and an operation receipt appearing — become an immediate change under
Reduce Motion.

The rounded sentinel/beacon app icon is Standfast's product identity; it does not report
live runner state. Its checked-in [1024×1024 source](Resources/AppIcon.png) contains no text
or third-party mark, is compiled into the complete `Standfast.icns` family by
`Scripts/build-icon.sh` during `make app`, and is included before the bundle is signed.

## What it is building, and for how long

Open the Control Center on a busy runner and its card says which job:

```
mac-mini-m4 — Running a job
Running testflight — 1m 20s, usually 2m 50s
```

Under it, the last five jobs show how each one ended and how long it took. The job's name,
its history and the usual duration all come out of the log the runner already writes beside
itself — **no extra API call and nothing to configure**. The runner announces every job it
picks up and every result it hands back, and Standfast reads the tail of that file. Whether
the runner is busy right now is still GitHub's answer, from the same status request the
card already makes, so the running line appears only once GitHub says so.

"Usually" is the median of the last few **successful** runs *of that same job*. Not the
mean, and not every run: a build cancelled after ten seconds is a real event and a
terrible estimate, and one of them would drag a mean down by half a minute and keep it
there. **With fewer than three runs to go on, Standfast shows no estimate at all** —
elapsed time only. A number invented from two samples is worse than no number.

The line shows elapsed time against a reference, never a countdown. A job that overruns
keeps saying what it usually takes, which is exactly when you want to know.

## What the runner is costing you

A runner eats a disk quietly. On the machine this was built against, `_work` was 4.5 GB —
of which **4.33 GB was the hosted tool cache** — and `_diag` was 9 MB growing by about ten
a day, with no rotation of any kind. Nobody looks at either until the disk is full.

Each runner card's **Maintenance** group measures both, broken down by what each directory
is *for* rather than as one total:

```
Tool cache — 4.33 GB
Repository checkouts — 431 MB
Downloaded actions — 16.6 MB
Logs — 9.2 MB
Measured 4m ago
```

The breakdown is the point. 4.5 GB is a number to be alarmed by; 4.33 GB of *cache* is a
number to press a button about. It is measured with `du` when you ask, never on a timer,
and the runner card's Maintenance group says how old the numbers are.

Standfast offers to delete exactly three things, and the shortness of that list is the
feature:

| Offered | Why |
|---|---|
| `_work/_tool` | The hosted tool cache. An `actions/setup-*` step downloads it back. |
| `_work/_actions` | The actions your workflows use. The runner re-fetches any it cannot find. |
| Old `_diag` logs | Nothing written to in over a week, worker logs above all. |

**The repository checkouts are never offered.** Nothing in one is a cache: a workflow that
wrote a file git does not track loses it, and the next run pays for a full clone where it
would have paid for a fetch. `_work/_temp` is not offered either — it reads as the safest
of the lot and is the most dangerous, because it is `$RUNNER_TEMP`, it holds the scripts of
a job in flight, and it is empty whenever the runner is idle.

Deleting is offered **only while that runner is idle or stopped**, read off that runner and
never off the fleet, and the state is checked again immediately before anything goes — a
job can arrive between the click and the delete. The deletion itself is a rename: the
directory is moved aside in one atomic syscall and taken apart afterwards, so a job that
lands a microsecond late finds *no* tool cache, which is a slower build, rather than half a
tool cache, which is a failed one.

The log the runner is writing right now is never deleted, and neither is the history the
Control Center shows you.

## Open at login

Off by default, and switched on from Settings. Standfast asks macOS to register it and
then asks macOS back what actually happened, so the checkbox shows the state of the
registration rather than the state of the request — including the case where macOS keeps
the registration and the user has switched it off in System Settings, where nothing failed
and the app still will not launch.

## Availability

No Standfast release or Homebrew tap has been published. The v0.5.0 interface described
here remains `Unreleased`; there is no supported stable-install command or downloadable
artifact yet. Tagging, signing, notarization, the final formula SHA, tap creation and
publication remain with the release manager.

Contributors can assemble an ad-hoc local app from an existing checkout of this source
state using the verified [building-from-source workflow](#building-from-source) below. That
development bundle is not a published or distributable release.

### Requirements

- macOS 14 or later.
- A runner to watch: one **installed as a service** — the one `./svc.sh install` sets up —
  is found on its own. One started by hand with `./run.sh` is watched once you add its
  folder in Settings.
- A way to ask GitHub, either of:
  - a GitHub token pasted into Settings, which Standfast keeps in your login Keychain and
    uses for its requests to `api.github.com`; or
  - the [GitHub CLI](https://cli.github.com), authenticated once with `gh auth login`.
    Standfast uses it only while no token is stored.

  Queued work needs the token: the `gh` path never answers it, because what it returns
  cannot be attributed to a runner's labels.

## There is nothing to configure

Standfast finds your runners the way launchd does. It reads the LaunchAgent each runner
installed, and the `.runner` file each one keeps beside itself:

```
~/Library/LaunchAgents/actions.runner.<owner>-<repo>.<name>.plist   → where it lives
<runner directory>/.runner                                          → who it is
```

No path to type and no repository to name. If `gh` is already signed in, there is no token
to paste either. Several runners on one Mac work out of the box and are told apart by where
they are registered when they share a name. Runners registered to an **organisation** or to
a GitHub Enterprise Cloud **account** work too.

Three other kinds of runner are found from where they already describe themselves:

- **GitLab runners**, from gitlab-runner's own `~/.gitlab-runner/config.toml`. Their state
  comes from the GitLab instance each one names, asked with a GitLab token from Settings.
  The runner's own token stays in that file; Standfast never uses it.
- **Supervisor-managed ephemeral fleets**, from the read-only status snapshot that
  `actions-runner-fleet` publishes at `~/.local/state/actions-runner-fleet/status-v1.json`.
  Standfast watches their slots; starting, stopping and cleaning them belong to the
  supervisor.
- **Runners started by hand with `./run.sh`**, which leave no LaunchAgent. They are never
  guessed by walking the disk: you add their folder in Settings, and Standfast re-reads it
  on every scan and watches the runner's process. It cannot start or stop them, and says so
  beside the controls.

Each runner is asked about by its own `agentId`, so a second runner on the same repository
can never be mistaken for the first.

## Known limitations

These are real and deliberate, not oversights:

- **Runners started by hand with `./run.sh` are not found on their own.** They leave no
  LaunchAgent, so their folder has to be added in Settings, and Standfast can watch them but
  not start or stop them. They must run under your own account: Standfast looks only at
  your processes, never at another user's.
- **GitHub Enterprise Server is not supported.** The host in the runner's `gitHubUrl` is
  parsed for the scope and then thrown away: status is asked of `api.github.com` — or of
  `github.com` through `gh` when no token is stored — and the workflow-runs or
  runner-settings destination is built there too. A GHES runner reads `unknown`. (Runners
  registered to a GitHub Enterprise Cloud *account* — `github.com/enterprises/...` — do
  work.)
- **Queued work is answered only for repository runners.** GitHub has no endpoint that
  lists what is waiting at organization or enterprise level, so those runners say the
  question cannot be answered there instead of showing an empty queue.
- **State is re-read every 15 seconds**, and a slow answer from GitHub or `gh` can stretch
  that. The menu says when it last looked, which is the only honest way to tell.
- **The job history goes back about twenty jobs**, and no further. It is read from the
  tail of the runner's own logs; anything older is a question for the repository's GitHub
  workflow-runs page. Organization and enterprise runners have no honest cross-repository
  runs page, so their button opens runner settings instead.
- **A half-uninstalled runner nags forever.** If a `.plist` is left behind without its
  runner directory, the Control Center keeps it visible as unreadable and the quick menu
  surfaces a compact discovery warning. Delete the stray `.plist` to clear it.
- **A returned service command is not a proved state.** `svc.sh start` can exit 0 before
  launchd and GitHub agree on the result, so Standfast reports the request as accepted and
  lets the following probes establish the runner's state. A timeout remains explicitly
  uncertain rather than being called success or failure.

## Privacy

Standfast itself adds no telemetry or analytics, and never checks for updates to *itself*.
Its GitHub requests are functional. It asks for each configured runner's status. For a
repository runner, it lists that repository's queued workflow runs and their jobs. It also
asks the public endpoint for the latest `actions/runner` release, so the Control Center can
say when an installed runner is out of date. That release request runs once when Standfast
launches and then no more often than every 24 hours while that same instance stays open;
relaunching starts a new instance and a new first check.

With a token stored in Settings, those requests go straight to `api.github.com` over HTTPS.
Without one, status and the release check
go through the installed GitHub CLI, launched with the environment Standfast inherited.
Current `gh` versions may send their own pseudonymous telemetry; Standfast neither adds to
nor suppresses that delegated behavior. GitHub documents the data and opt-out controls at
[GitHub CLI telemetry](https://cli.github.com/telemetry). In particular,
`GH_TELEMETRY=false` or `DO_NOT_TRACK=true` disables it for the inherited environment.

The only credentials Standfast keeps are the ones you paste into Settings — a GitHub token
and, if you watch GitLab runners, one token per GitLab instance — in your login Keychain.
Settings says whether one is stored and never what it is. A GitLab runner's status is asked
of the GitLab instance named in that runner's own `config.toml`, with that instance's token
only, and never over plain `http`: an instance served without TLS is not asked at all.

The app reads the runner's own `_diag` locally: listener-log contents provide job history
and the installed runner version, while file metadata and disk usage support maintenance.
After explicit confirmation, maintenance can delete eligible old logs. Standfast never
uploads `_diag` contents; see [SECURITY.md](SECURITY.md) for the complete boundary.

## Building from source

You need Xcode 16 or later; the Command Line Tools alone cannot build it, because from the
macOS 27 SDK on SwiftUI's `@State` is a macro whose plugin ships only inside Xcode.app.

```sh
swift package clean && swift test  # about 1,000 tests; no installed runner required
make app                           # assembles .build/Standfast.app
make check                         # strict local bundle, menu and window/AX lifecycle check
```

`make check` requires an unlocked graphical session and Accessibility permission for the
calling terminal. Missing permission or an unreadable menu/window tree is a failure. CI
explicitly runs `STANDFAST_AX_MODE=skip ./Scripts/check-app.sh` as a packaging/process
smoke test; its green result does **not** cover the status menu, Control Center, Settings,
focus, keyboard navigation, or window lifecycle.

The package is plain SwiftPM with no dependencies and no `.xcodeproj` — project files
generate unreadable merge conflicts and scare off contributors.

The code is split into two targets. `RunnerKit` holds everything with no UI — discovery,
the launchd probe, the GitHub client and the state machine. `Standfast` is the SwiftUI app
on top of it. Quick-menu, Control Center, operation feedback, per-runner button rules and
settling behavior are plain presentation values rather than decisions buried in view code,
so the tests can read them. Both targets are tested, and the whole suite runs on a machine
with no runner installed.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
conventions this codebase actually enforces, and for the list of changes that look
like obvious cleanups and are regressions.

## Licence

MIT. See [LICENSE](LICENSE). What changed and when is in
[CHANGELOG.md](CHANGELOG.md).
