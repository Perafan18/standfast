# Security

## What Standfast can reach

Standfast runs as your user and never elevates privileges. Features normally use the
permissions that user already has; the opt-in notification switches ask macOS for
notification authorization when you enable one. Standfast:

- reads `~/Library/LaunchAgents/actions.runner.*.plist` and the `.runner` file inside each
  runner directory, plus the runner's `_work` and `_diag` directories. Listener-log
  contents in `_diag` provide local job history and the installed runner version; file
  metadata and disk usage support maintenance;
- runs `/bin/launchctl list` to ask launchd whether a service is alive;
- runs `/bin/bash` on your runner's own `svc.sh` to start and stop it, in that runner's
  own directory;
- runs `/usr/bin/du` to measure the runner directories shown by housekeeping;
- runs the GitHub CLI to ask the API about runner status and the public latest
  `actions/runner` release — `/usr/bin/env gh` first, then `/opt/homebrew/bin/gh` and
  `/usr/local/bin/gh`. The first resolves through your `PATH` so a `gh` installed and
  configured through mise, nix, asdf or another chosen toolchain is respected; whichever
  executable runs receives the inherited environment described below;
- opens the configured runner's GitHub settings URL in your default browser when you ask;
- stores notification and sleep-prevention switches in `UserDefaults`, asks macOS to
  register or unregister its login item when you change that switch, and posts the
  notifications you enable;
- while sleep prevention is enabled and at least one runner has work, holds a macOS
  `.idleSystemSleepDisabled` activity assertion; it releases the assertion when the switch
  is disabled, when the next completed scan observes no remaining work, or when the
  Standfast process exits; and
- after an explicit housekeeping confirmation, creates a temporary directory inside the
  runner's `_work`, moves and deletes the selected caches, or deletes the eligible old
  diagnostic logs in `_diag` while preserving the active and retained listener logs.

Standfast opens no listening ports, has no telemetry or analytics, and never checks for
updates to Standfast itself. Its outgoing GitHub requests are functional: runner-status
requests identify the configured scope and runner, while the latest-runner-release request
uses a public endpoint. Standfast does not upload `_diag` contents or other job data.

Standfast launches `gh` with the environment it inherited; it neither injects nor removes
GitHub authentication or update-notifier variables. Depending on the installed `gh`
version and configuration, `gh` may perform its own update check or related traffic when
invoked. Standfast does not initiate that delegated check or inspect whether it occurred:
the only API calls it explicitly asks `gh` to make are runner status and the public latest
`actions/runner` release.

## No sudo, ever

On macOS a self-hosted runner is a per-user LaunchAgent. Standfast never invokes `sudo` or
another privilege-elevation mechanism, and a change that introduces one will not be
merged.

## Credentials

Standfast **stores no token of its own**. It calls `gh` with the inherited environment and
leaves credential selection to that CLI. For `github.com`, `gh` documents `GH_TOKEN` and
then `GITHUB_TOKEN` as taking precedence over credentials previously stored by `gh auth
login`; when neither is set, `gh` can use its own stored authentication. Standfast never
inspects, reads, copies or logs any of those tokens or credentials.

A consequence worth stating plainly: the `gh` process has the authority of whichever
credential it selects. Standfast's explicit `gh` requests only read runner status and the
public latest runner release; starting and stopping the local service does not use GitHub.

## Command execution

Every external command goes through `CommandRunning` with an explicit executable and
argument vector. Standfast does not concatenate executable names or argument values into
a single command string for `sh -c` or `bash -c`. For runner operations, the working
directory and runner base path come from the LaunchAgent plist; derived script and work
paths remain individual argument values, so spaces and quotes in them are treated
literally.

For service control the executable is `/bin/bash`, the argument vector is
`[<runner>/svc.sh, start|stop]`, and the process working directory is the runner directory.
Bash receives the script path and verb as arguments, not as a command string. This also
lets a restored runner's bash script work when its execute bit is missing.

`stdin` is `/dev/null`, so a subprocess receives EOF instead of interactive input.
`stderr` is discarded rather than mixed into the stdout Standfast parses.

## Reporting a vulnerability

Please report privately rather than in a public issue: open a
[security advisory](https://github.com/Perafan18/standfast/security/advisories/new) on the
repository. You will get an acknowledgement within a few days.

This is a small hobby project maintained by one person. There is no bounty and no formal
SLA, but genuine reports will be taken seriously and credited unless you prefer otherwise.
