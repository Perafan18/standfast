# Security

## What Standfast can reach

Standfast runs as your user, with your permissions, and does not ask for more. It:

- reads `~/Library/LaunchAgents/actions.runner.*.plist` and the `.runner` file inside each
  runner directory, plus the runner's `_work` and `_diag` directories for disk usage and
  local job history — files you can already read;
- runs `/bin/launchctl list` to ask launchd whether a service is alive;
- runs `/bin/bash` on your runner's own `svc.sh` to start and stop it, in that runner's
  own directory;
- runs `/usr/bin/du` to measure the runner directories shown by housekeeping;
- runs the GitHub CLI to ask the API about runner status and the public latest
  `actions/runner` release — `/usr/bin/env gh` first, then `/opt/homebrew/bin/gh` and
  `/usr/local/bin/gh`. The first of those resolves
  through your `PATH`, on purpose: a `gh` from mise, nix or asdf is a deliberate choice
  and the only one holding the credentials you meant to use;
- opens the configured runner's GitHub settings URL in your default browser when you ask;
- stores notification and sleep-prevention switches in `UserDefaults`, asks macOS to
  register or unregister its login item when you change that switch, and posts the
  notifications you enable; and
- after an explicit housekeeping confirmation, creates a temporary directory inside the
  runner's `_work`, moves and deletes the selected caches, or deletes the eligible old
  diagnostic logs in `_diag` while preserving the active and retained listener logs.

Standfast opens no listening ports, has no telemetry or analytics, and never checks for
updates to Standfast itself. Its outgoing GitHub requests are functional: runner-status
requests identify the configured scope and runner, while the latest-runner-release request
uses a public endpoint. Standfast does not upload `_diag` contents or other job data.

## No sudo, ever

On macOS a self-hosted runner is a per-user LaunchAgent. `sudo` is the Linux instruction
and would only produce a password prompt this app has no way to answer. Standfast never
elevates privileges, and a change that introduces `sudo` will not be merged.

## Credentials

Standfast **stores no token of its own**. It calls `gh`, which uses the credentials you
authenticated once with `gh auth login` and which live in `gh`'s own storage — its config
directory and the system Keychain. Standfast never reads, copies or logs them.

A consequence worth stating plainly: Standfast can do anything to your runners that your
`gh` credentials permit. It only ever reads runner status and starts or stops the local
service, but the authority it borrows is yours.

## Command execution

Every external command goes through one seam, `CommandRunning`, and every one is invoked
with an explicit argument vector — never through a shell. Paths come from your own home
directory and can contain spaces and quotes; passing them through `sh -c` would turn that
into an injection surface, so it is not done anywhere in the codebase.

`svc.sh` is the one command handed to `/bin/bash`, and that is not the same thing. It is
run as `bash <path> start`, an interpreter given a script and one literal argument — a
runner directory restored from a backup often arrives without the execute bit, and it is
a bash script either way. Nothing is ever concatenated into a command string.

`stdin` is `/dev/null` and `stderr` is discarded, so a subprocess cannot prompt you or
smuggle output into a parsed result.

## Reporting a vulnerability

Please report privately rather than in a public issue: open a
[security advisory](https://github.com/Perafan18/standfast/security/advisories/new) on the
repository. You will get an acknowledgement within a few days.

This is a small hobby project maintained by one person. There is no bounty and no formal
SLA, but genuine reports will be taken seriously and credited unless you prefer otherwise.
