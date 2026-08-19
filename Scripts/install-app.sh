#!/bin/bash
# Puts a freshly built Standfast.app in ~/Applications, keeping a bounded
# number of the versions it replaces.
#
# Bounded is the point. This replaces a command that was retyped by hand every
# time and backed up unconditionally, which is how six copies of the app came
# to live in ~/Applications — invisible in the folder, obvious in Spotlight,
# where "Stan" returned seven identical icons whose names were all truncated
# before the timestamp that told them apart. A backup nobody prunes is not a
# safety net; it is a second copy of the problem.
#
# Two are kept because two is what a rollback needs: the version you were
# running, and the one before it in case the first was already wrong. Older
# than that is what git is for — every release is a tag and every change is a
# commit, so any build can be reproduced in a minute.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

INSTALL_DIR="${INSTALL_DIR:-$HOME/Applications}"
BACKUP_DIR="${BACKUP_DIR:-$INSTALL_DIR/Standfast Backups}"
BACKUPS_KEPT="${BACKUPS_KEPT:-2}"
# Whether to stop the copy that is running and start the one being installed.
# Off is for staging a version to run later, and for the contract tests, which
# must never touch the operator's real menu bar app.
RESTART="${RESTART:-1}"
# A bundle to install. Unset means build one first, which is the normal case.
APP="${APP:-}"

if [ -z "$APP" ]; then
  DEST=.build/Standfast.app ./Scripts/build-app.sh
  APP=".build/Standfast.app"
fi

# Checked before anything is moved, backed up, or deleted. A build that failed
# and a path typed wrong arrive here looking identical, and in both cases the
# copy already installed is the only working one there is.
if [ ! -f "$APP/Contents/MacOS/Standfast" ]; then
  echo "install-app.sh: $APP is not a Standfast bundle" >&2
  exit 1
fi

INSTALLED="$INSTALL_DIR/Standfast.app"

if [ -d "$INSTALLED" ] && [ "$BACKUPS_KEPT" -gt 0 ]; then
  mkdir -p "$BACKUP_DIR"
  # The stamp is the name rather than a mtime because mtimes do not survive
  # being copied, restored from Time Machine, or synced — and the name is what
  # the pruning below sorts on.
  cp -R "$INSTALLED" "$BACKUP_DIR/Standfast-$(date +%Y%m%d-%H%M%S).app"
fi

if [ -d "$BACKUP_DIR" ]; then
  # Newest first, then everything past the limit goes. `|| true` because an
  # empty directory is a normal state, not a failure — grep says so with an
  # exit code that would otherwise take the whole script down.
  stale="$(ls -1 "$BACKUP_DIR" 2>/dev/null \
    | grep '^Standfast-.*\.app$' \
    | sort -r \
    | tail -n "+$((BACKUPS_KEPT + 1))" || true)"
  if [ -n "$stale" ]; then
    while IFS= read -r old; do
      rm -rf "$BACKUP_DIR/$old"
      echo "Pruned $old"
    done <<< "$stale"
  fi
fi

if [ "$RESTART" = 1 ]; then
  # Before the swap, not after: replacing the bundle under a running process
  # leaves it holding an executable that no longer exists on disk, which is
  # how two Standfasts ended up in the menu bar once already.
  pkill -x Standfast 2>/dev/null || true
fi

mkdir -p "$INSTALL_DIR"
# Staged next to the destination and moved into place, so an interrupted copy
# leaves the previous version intact rather than half of the new one.
STAGED="$INSTALL_DIR/.Standfast-installing.app"
rm -rf "$STAGED"
cp -R "$APP" "$STAGED"
rm -rf "$INSTALLED"
mv "$STAGED" "$INSTALLED"
# LaunchServices caches bundle metadata by mtime; the same reason build-app.sh
# ends this way.
touch "$INSTALLED"

echo "Installed $INSTALLED"

if [ "$RESTART" = 1 ]; then
  open "$INSTALLED"
  echo "Relaunched"
fi
