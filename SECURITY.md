# Security

## What Standfast can reach

Standfast runs as your user and never elevates privileges. Features normally use the
permissions that user already has; the opt-in notification switches ask macOS for
notification authorization when you enable one. Standfast:

- reads `~/Library/LaunchAgents/actions.runner.*.plist` and the `.runner` file inside each
  runner directory, plus the runner's `_work` and `_diag` directories. Listener-log
  contents in `_diag` provide local job history and the installed runner version; file
  metadata and disk usage support maintenance;
- reads the same `.runner` file in each folder you add in Settings for a runner started by
  hand with `./run.sh`;
- reads gitlab-runner's `~/.gitlab-runner/config.toml` when it exists, for each runner's
  id, name and instance address. The file also holds each runner's own token; Standfast
  reads past it with the rest of the file but never keeps, uses or sends it;
- reads the read-only fleet snapshot at
  `~/.local/state/actions-runner-fleet/status-v1.json` when a supervisor publishes one;
- runs `/bin/launchctl list` to ask launchd whether a service is alive;
- runs `/bin/ps` to find a runner's process, listing only your own processes: for a
  hand-started runner, `/usr/bin/env LC_ALL=en_US.UTF-8 /bin/ps -wwo command= -U <your user
  id>`, so a folder with accented characters is printed as itself; for gitlab-runner,
  `/bin/ps -wwo command= -U <your user id>`. The output is matched in memory and never
  stored or sent;
- runs `/bin/bash` on your runner's own `svc.sh` to start and stop it, in that runner's
  own directory;
- runs `/usr/bin/du` to measure the runner directories shown by housekeeping;
- with a GitHub token stored in Settings, sends HTTPS requests to `api.github.com` with
  that token: each runner's status, the public latest `actions/runner` release, and — for
  repository runners only — that repository's queued workflow runs and their jobs;
- with no GitHub token stored, runs the GitHub CLI for runner status and the latest
  release instead — `/usr/bin/env gh` first, which resolves through your `PATH`, then the
  fixed places package managers install it: `/opt/homebrew/bin/gh`, `/usr/local/bin/gh`,
  `/opt/local/bin/gh`, `/etc/profiles/per-user/<user>/bin/gh`,
  `/run/current-system/sw/bin/gh`, `~/.nix-profile/bin/gh`,
  `~/.local/share/mise/shims/gh` and `~/.asdf/shims/gh`. The fixed list matters because an
  app opened from Finder, the Dock or at login inherits only
  `/usr/bin:/bin:/usr/sbin:/sbin`. Whichever executable runs receives the inherited
  environment described below;
- with a GitLab token stored in Settings for an instance, sends `GET /api/v4/runners/<id>`
  to that instance, at the scheme, host, port and path its runners' `config.toml` names,
  carrying that instance's token only. An instance served over plain `http` is not asked
  at all, so its token is never sent unencrypted;
- opens GitHub workflow runs for repository-scoped runners, or the runner settings page
  for organization- and enterprise-scoped runners, or — for a GitLab runner — the GitLab
  instance its `config.toml` names, which may be a plain `http` address, in your default
  browser when you ask;
- stores its switches, the folders you add for hand-started runners, which runner cards
  you folded, the Dock preference, and the names of the GitLab instances that have had a
  token card — never a token — in `UserDefaults`, so a token for an instance `config.toml`
  no longer names keeps its Remove button across launches; asks macOS to register or
  unregister its login item when you change that switch; and posts the notifications you
  enable;
- while sleep prevention is enabled and at least one runner has work, holds a macOS
  `.idleSystemSleepDisabled` activity assertion; it releases the assertion when the switch
  is disabled, when the next completed scan observes no remaining work, or when the
  Standfast process exits; and
- after an explicit housekeeping confirmation, creates a temporary directory inside the
  runner's `_work`, moves and deletes the selected caches, or deletes the eligible old
  diagnostic logs in `_diag` while preserving the active and retained listener logs.

Before housekeeping measures or deletes anything, it resolves the runner, work and
diagnostics paths and refuses a target that resolves outside the runner. A runner whose
work folder is configured outside its own directory is still watched, but housekeeping
abstains for it and says why. A `_work/_tool` or `_work/_actions` that is itself a
symbolic link — a cache kept on another disk, for instance — is left in place. Its private
trash directory must be a real directory rather than a symbolic link. These pathname
checks protect against stale or accidental filesystem configuration; they are not a
sandbox against another process running concurrently as the same user. Such a process
already has the same file authority and can replace a checked path before the next
filesystem call. Eliminating that race would require descriptor-relative operations such
as `openat`, `renameat` and `unlinkat` with no-follow checks.

Standfast opens no listening ports, adds no telemetry or analytics of its own, and never
checks for updates to Standfast itself. Its outgoing requests are functional:
runner-status requests identify the configured scope and runner, queued-work requests
identify the repository, and the latest-runner-release request uses a public endpoint.
Standfast does not upload `_diag` contents or other job data.

When it uses `gh`, Standfast launches it with the environment it inherited; it neither
injects nor removes GitHub authentication, update-notifier, or telemetry variables. Current
`gh` versions may send their own pseudonymous telemetry unless the user disables it; see
[GitHub CLI telemetry](https://cli.github.com/telemetry). `GH_TELEMETRY=false` or
`DO_NOT_TRACK=true` disables that telemetry in the environment Standfast inherits.
Depending on the installed `gh` version and configuration, `gh` may also perform its own
update check or other related traffic when invoked. Standfast does not initiate or inspect
those delegated behaviors: the only API calls it explicitly asks `gh` to make are runner
status and the public latest `actions/runner` release.

## No sudo, ever

On macOS a self-hosted runner is a per-user LaunchAgent. Standfast never invokes `sudo` or
another privilege-elevation mechanism, and a change that introduces one will not be
merged.

## Credentials

Standfast keeps **only the tokens you paste into Settings**, and both are optional:

- a GitHub token, as a generic-password item in your login Keychain under the service
  `dev.standfast.app` and the account `github-token`;
- a GitLab token per GitLab instance, in the same service under the account
  `gitlab-token@<instance>`, so one instance's token is never offered to another.

Each is a generic-password item in the login Keychain, which does not sync: it can be read
while that keychain is unlocked, and only by an app on the item's access list, which is why
a rebuilt app is asked once. Settings says whether a token is
stored and never displays it, and **Remove token** deletes the Keychain item. Standfast
never writes a token to `UserDefaults`, a file or a log. The token is re-read from the
Keychain for each request rather than held in memory, off the main thread and through a
gate that keeps one read per item in flight: a locked Keychain, or one asking whether this
build may read the item, raises one dialog rather than one per runner, and a refusal is
not asked again every refresh until you save or remove the token in Settings.

Every request goes only to the origin it was addressed to: a redirect to another scheme,
host or port is not followed, because the request carries a credential.

A refused token or a rate limit is reported as such. It never quietly falls through to
`gh`, which would hide a credential you deliberately configured being wrong.

When no GitHub token is stored, Standfast calls `gh` with the inherited environment and
leaves credential selection to that CLI. For `github.com`, `gh` documents `GH_TOKEN` and
then `GITHUB_TOKEN` as taking precedence over credentials previously stored by `gh auth
login`; when neither is set, `gh` can use its own stored authentication. Standfast never
inspects, reads, copies or logs any of those tokens or credentials. It also never uses a
runner's own credentials: it does not open the actions runner's `.credentials` files, and
it never keeps or sends the runner tokens in gitlab-runner's `config.toml`.

A consequence worth stating plainly: a request carries the authority of whichever
credential made it — your stored token or the one `gh` selects. Standfast only reads with
it: runner status, queued runs and their jobs, and the public latest runner release.
Starting and stopping the local service does not use GitHub.

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
