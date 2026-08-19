#!/bin/bash
# What installing Standfast over an existing copy is allowed to do to the copy
# it replaces.
#
# The script under test exists because the ad-hoc command it replaces kept
# every backup it ever made. Six of them accumulated in ~/Applications before
# anyone noticed, and the way they were noticed was Spotlight: seven results
# for "Stan", identical icons, names truncated exactly where they would have
# started to differ. Pruning is therefore the behaviour with the most tests
# here — it is the whole reason the script is a script.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
INSTALL="$ROOT/Scripts/install-app.sh"
FIXTURES="$(mktemp -d "${TMPDIR:-/tmp}/standfast-install.XXXXXX")"
trap 'rm -rf "$FIXTURES"' EXIT

failures=0
case_number=0
case_name=""
case_dir=""

begin_case() {
  case_number=$((case_number + 1))
  case_name="$1"
  case_dir="$FIXTURES/case-$case_number"
  mkdir -p "$case_dir/Applications"
}

# A bundle with a readable marker inside, so a test can tell two versions
# apart. Which copy ends up where is the entire question, and comparing paths
# alone cannot answer it.
make_app() {
  local path="$1" marker="$2"
  mkdir -p "$path/Contents/MacOS"
  printf '%s\n' "$marker" > "$path/Contents/MacOS/Standfast"
}

marker_of() {
  cat "$1/Contents/MacOS/Standfast" 2>/dev/null || printf '<missing>\n'
}

# RESTART=0 because a contract test must not stop or start the operator's real
# menu bar app. It is an option the script offers rather than a hook the test
# reaches through: installing without launching is what you want when you are
# staging a version to run later.
run_install() {
  # Through `env` rather than a bare assignment prefix: an assignment that
  # arrives by expanding "$@" is a command name to bash, not an assignment, so
  # the per-case overrides would silently become "command not found".
  env APP="$case_dir/new.app" \
    INSTALL_DIR="$case_dir/Applications" \
    BACKUP_DIR="$case_dir/Applications/Standfast Backups" \
    RESTART=0 \
    "$@" \
    bash "$INSTALL" 2>&1
}

expect_equal() {
  local what="$1" actual="$2" expected="$3"
  if [ "$actual" = "$expected" ]; then
    printf 'PASS: %s — %s\n' "$case_name" "$what"
  else
    printf 'FAIL: %s — %s is %s, expected %s\n' \
      "$case_name" "$what" "$actual" "$expected" >&2
    failures=$((failures + 1))
  fi
}

backup_count() {
  ls -1 "$case_dir/Applications/Standfast Backups" 2>/dev/null | wc -l | tr -d ' '
}

backup_names() {
  ls -1 "$case_dir/Applications/Standfast Backups" 2>/dev/null | sort | tr '\n' ' '
}

# ---------------------------------------------------------------------------

begin_case "a first install leaves no backup behind"
make_app "$case_dir/new.app" v1
run_install > /dev/null
expect_equal "the installed app" \
  "$(marker_of "$case_dir/Applications/Standfast.app")" "v1"
expect_equal "backups after installing over nothing" "$(backup_count)" "0"

# ---------------------------------------------------------------------------

begin_case "reinstalling keeps the version it replaced"
make_app "$case_dir/Applications/Standfast.app" old
make_app "$case_dir/new.app" new
run_install > /dev/null
expect_equal "the installed app" \
  "$(marker_of "$case_dir/Applications/Standfast.app")" "new"
expect_equal "backups" "$(backup_count)" "1"
# The backup must hold the version that was displaced, not another copy of the
# one that displaced it. A backup of the new app is worse than no backup: it
# looks like a safety net and restores nothing.
expect_equal "what the backup holds" \
  "$(marker_of "$case_dir/Applications/Standfast Backups"/*.app)" "old"

# ---------------------------------------------------------------------------

begin_case "old backups are pruned to the limit, newest kept"
make_app "$case_dir/Applications/Standfast.app" current
make_app "$case_dir/new.app" newest
mkdir -p "$case_dir/Applications/Standfast Backups"
for stamp in 20260101-000000 20260102-000000 20260103-000000; do
  make_app "$case_dir/Applications/Standfast Backups/Standfast-$stamp.app" "$stamp"
done
run_install BACKUPS_KEPT=2 > /dev/null
expect_equal "backups after pruning" "$(backup_count)" "2"
# The one just made plus the newest of the three, and nothing older. Sorted by
# name because the stamp is the name: a filesystem mtime survives neither a
# copy nor a restore from Time Machine.
kept="$(backup_names)"
case "$kept" in
  *"Standfast-20260103-000000.app"*) ;;
  *)
    printf 'FAIL: %s — pruning dropped the newest of the old backups: %s\n' \
      "$case_name" "$kept" >&2
    failures=$((failures + 1))
    ;;
esac
case "$kept" in
  *"Standfast-20260101-000000.app"* | *"Standfast-20260102-000000.app"*)
    printf 'FAIL: %s — pruning kept a backup older than the limit: %s\n' \
      "$case_name" "$kept" >&2
    failures=$((failures + 1))
    ;;
  *) ;;
esac

# ---------------------------------------------------------------------------

begin_case "BACKUPS_KEPT=0 keeps nothing"
make_app "$case_dir/Applications/Standfast.app" old
make_app "$case_dir/new.app" new
run_install BACKUPS_KEPT=0 > /dev/null
expect_equal "the installed app" \
  "$(marker_of "$case_dir/Applications/Standfast.app")" "new"
expect_equal "backups when none are wanted" "$(backup_count)" "0"

# ---------------------------------------------------------------------------

begin_case "a missing source does not destroy the installed app"
make_app "$case_dir/Applications/Standfast.app" precious
# No new.app is created: this is the shape of a build that failed, or a path
# typed wrong. Either way the copy already installed is the only working one
# the operator has, and it must survive being pointed at nothing.
if run_install > /dev/null 2>&1; then
  printf 'FAIL: %s — installing from a missing bundle reported success\n' \
    "$case_name" >&2
  failures=$((failures + 1))
else
  printf 'PASS: %s — refused\n' "$case_name"
fi
expect_equal "the app that was already installed" \
  "$(marker_of "$case_dir/Applications/Standfast.app")" "precious"
expect_equal "backups made by a refused install" "$(backup_count)" "0"

# ---------------------------------------------------------------------------

if [ "$failures" -ne 0 ]; then
  printf '\n%s contract assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll install contract assertions passed\n'
