# Standfast

**A macOS menu bar app for self-hosted GitHub Actions runners.** It tells you, without a
click, whether your runner is actually going to get work — and lets you start, stop and
restart it when it isn't.

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

## What the icon means

| Icon | State | Meaning |
|---|---|---|
| ✓ | `idle` | Registered, connected, waiting for work. The one you want to see. |
| ⚙ | `busy` | Running a job right now. |
| ⚠ | `disconnected` | The process is alive, but GitHub cannot see it. No job is coming. |
| ☾ | `stopped` | The service is not running. Start it from the menu. |
| ? | `unknown` | Standfast could not tell — and the menu says which of the reasons it was. |
| ↻ | `starting` | You just started it; GitHub has not acknowledged it yet. Held for 30s. |
| ◌ | — | This Mac has no runners at all. Not a failure to read one. |

`unknown` is never a shrug. It distinguishes *the GitHub CLI is not installed*, *it is
installed but not authenticated* (run `gh auth login`), *it answered nothing useful*, and
*launchd could not be asked* — because each one has a different fix.

## What it is building, and for how long

Open the menu on a busy runner and it says which job:

```
mac-mini-m4 — Running a job
Running testflight — 1m 20s, usually 2m 50s
```

Under it, the last five jobs with how each one ended and how long it took. All of it comes
out of the log the runner already writes beside itself — **no API call, no token, nothing
to configure**. The runner announces every job it picks up and every result it hands back,
and Standfast reads the tail of that file.

"Usually" is the median of the last few **successful** runs *of that same job*. Not the
mean, and not every run: a build cancelled after ten seconds is a real event and a
terrible estimate, and one of them would drag a mean down by half a minute and keep it
there. **With fewer than three runs to go on, Standfast shows no estimate at all** —
elapsed time only. A number invented from two samples is worse than no number.

The line shows elapsed time against a reference, never a countdown. A job that overruns
keeps saying what it usually takes, which is exactly when you want to know.

## Open at login

Off by default, and switched on from the menu. Standfast asks macOS to register it and
then asks macOS back what actually happened, so the checkbox shows the state of the
registration rather than the state of the request — including the case where macOS keeps
the registration and the user has switched it off in System Settings, where nothing failed
and the app still will not launch.

## Install

```sh
brew install perafan18/tap/standfast
```

The formula builds from source, so nothing arrives quarantined and there is no
"unidentified developer" dialog to argue with.

The tap is a separate repository and goes up with the first tagged release. Until then,
this repository is itself a tap, and the formula in it installs the same thing from
`main`:

```sh
brew tap perafan18/standfast https://github.com/Perafan18/standfast
brew install --HEAD perafan18/standfast/standfast
```

(A formula file cannot be installed by path — Homebrew requires it to be in a tap.)

Either way, link it where macOS expects to find applications:

```sh
ln -sfn "$(brew --prefix)/opt/standfast/Standfast.app" /Applications/Standfast.app
```

### Requirements

- macOS 14 or later.
- A runner **installed as a service** — the one `./svc.sh install` sets up.
- The [GitHub CLI](https://cli.github.com), authenticated once with `gh auth login`.
  Standfast borrows those credentials and never stores a token of its own.

## There is nothing to configure

Standfast finds your runners the way launchd does. It reads the LaunchAgent each runner
installed, and the `.runner` file each one keeps beside itself:

```
~/Library/LaunchAgents/actions.runner.<owner>-<repo>.<name>.plist   → where it lives
<runner directory>/.runner                                          → who it is
```

No path to type, no repository to name, no token to paste. Several runners on one Mac work
out of the box and are told apart by where they are registered when they share a name.
Runners registered to an **organisation** or to a GitHub Enterprise Cloud **account**
work too.

Each runner is asked about by its own `agentId`, so a second runner on the same repository
can never be mistaken for the first.

## Known limitations

These are real and deliberate, not oversights:

- **Runners started by hand with `./run.sh` are not discovered.** They leave no
  LaunchAgent, and the whole discovery mechanism is a scan of `~/Library/LaunchAgents`.
- **GitHub Enterprise Server is not supported.** The host in the runner's `gitHubUrl` is
  parsed for the owner and repository and then thrown away: status is asked of
  `github.com` through `gh`, and "Open on GitHub" links there too. A GHES runner reads
  `unknown`. (Runners registered to a GitHub Enterprise Cloud *account* —
  `github.com/enterprises/...` — do work.)
- **State is re-read every 15 seconds**, and a slow `gh` can stretch that. The menu now
  says when it last looked, which is the only honest way to tell.
- **The job history goes back about twenty jobs**, and no further. It is read from the
  tail of the runner's own logs; anything older is a question for GitHub's run list.
- **A half-uninstalled runner nags forever.** If a `.plist` is left behind without its
  runner directory, the menu lists it as unreadable every time you open it. Delete the
  stray `.plist` to clear it.
- **Failures are not notified.** `svc.sh start` exits 0 even when launchd refused the load,
  so the only honest signal is the row going back to "Stopped" on the next refresh.

## Privacy

Nothing leaves your machine. Standfast talks to launchd, to your runner's own `svc.sh`,
and to the GitHub API through `gh`. It reads files you can already read — including the
runner's own `_diag` logs, which never leave the machine either — stores no credentials,
and has no telemetry, no analytics and no update check.

See [SECURITY.md](SECURITY.md).

## Building from source

```sh
git clone https://github.com/Perafan18/standfast
cd standfast
make test      # 342 tests, none of which needs a runner installed
make app       # assembles Standfast.app
make run       # assembles and launches it
make check     # the packaging check: assembles, deletes .build, launches
```

The package is plain SwiftPM with no dependencies and no `.xcodeproj` — project files
generate unreadable merge conflicts and scare off contributors.

The code is split into two targets. `RunnerKit` holds everything with no UI —
discovery, the launchd probe, the GitHub client and the state machine. `Standfast` is
the SwiftUI menu bar app on top of it, and the menu's copy, its per-runner button rules
and its settling window are plain values there rather than view code, so the tests can
read them. Both targets are tested, and the whole suite runs on a machine with no
runner installed.

## Contributing

Issues and pull requests are welcome. See [CONTRIBUTING.md](CONTRIBUTING.md) for the
conventions this codebase actually enforces, and for the list of changes that look
like obvious cleanups and are regressions.

## Licence

MIT. See [LICENSE](LICENSE). What changed and when is in
[CHANGELOG.md](CHANGELOG.md).
