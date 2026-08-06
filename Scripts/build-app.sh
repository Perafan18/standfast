#!/bin/bash
# Assembles Standfast.app out of the SwiftPM build product.
#
# A script rather than an .xcodeproj on purpose: project files produce merge
# conflicts nobody can read, and a contributor who has to open Xcode to change
# a string is a contributor who does not.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

CONFIG="${CONFIG:-release}"
DEST="${DEST:-.build/Standfast.app}"

swift build -c "$CONFIG" --product Standfast
BIN="$(swift build -c "$CONFIG" --show-bin-path | tail -n 1)"

EXECUTABLE="$BIN/Standfast"
# Named after the package and the target, both of which are "Standfast".
RESOURCES="$BIN/Standfast_Standfast.bundle"

# Loudly, not with `|| true`. A missing catalogue costs the user their own
# language, and the app is built to survive that rather than crash — which
# means a packaging mistake here would ship and never be noticed.
for required in "$EXECUTABLE" "$RESOURCES"; do
  if [ ! -e "$required" ]; then
    echo "build-app.sh: $required is missing; the build did not produce it" >&2
    exit 1
  fi
done

rm -rf "$DEST"
mkdir -p "$DEST/Contents/MacOS" "$DEST/Contents/Resources"

cp "$EXECUTABLE" "$DEST/Contents/MacOS/Standfast"
cp Resources/Info.plist "$DEST/Contents/Info.plist"

# Both halves of the localisation, and they are not redundant.
#
# The SwiftPM bundle is what `L10n.resourceBundle` looks for by name, and it
# has to land somewhere `Bundle.main` can reach: Contents/Resources is
# `Bundle.main.resourceURL`, which is one of the places the accessor searches,
# and it is the only one of them that leaves the `.app` a well-formed bundle —
# anything sitting next to Contents/ is unsealed content that `codesign`
# refuses, which would have to be undone the day this app gets notarised.
cp -R "$RESOURCES" "$DEST/Contents/Resources/"

# The loose `.lproj` directories are what make Contents/Resources itself a
# localised bundle, so `Bundle.main` can answer in Spanish even if the bundle
# above were lost, and — with CFBundleLocalizations in Info.plist — what makes
# macOS offer Standfast in the per-app language picker.
cp -R "$RESOURCES"/*.lproj "$DEST/Contents/Resources/"

# Signing is not a release-only concern, and dropping it breaks the app.
#
# SwiftPM leaves the executable linker-signed with the identifier `Standfast`,
# and copying it into a bundle does not bind Info.plist to it. `codesign -dv`
# on the result says `Identifier=Standfast`, `Info.plist=not bound`,
# `Sealed Resources=none` — so as far as the system is concerned this process
# has no bundle identity, and `usernoted` will not register a bundle it cannot
# identify. Signing the whole bundle binds Info.plist and the identifier
# becomes `dev.standfast.app`, which is the precondition for a notification
# ever being delivered. `check-app.sh` asserts exactly that.
#
# Which identity is chosen, and why it is chosen in this order:
#
#   1. $SIGN_IDENTITY, when set. An explicit choice is never second-guessed,
#      and never silently downgraded — see the hard failure below.
#   2. A Developer ID Application certificate, when the keychain has one. This
#      is the only kind of certificate Gatekeeper accepts outside the App
#      Store, and the only one `notarytool` will take. Apple Development and
#      Apple Distribution certificates are deliberately NOT used: neither
#      notarises, so signing with one produces a bundle that looks signed,
#      passes `codesign --verify`, and is still refused on every Mac but this
#      one.
#   3. Ad-hoc, so a contributor with no certificate still gets a working app.
#
# Selection is by SHA-1 rather than by name on purpose: renewing a certificate
# leaves two in the keychain with the same common name, and `codesign` refuses
# an ambiguous match rather than picking one.
identities="$(security find-identity -v -p codesigning 2>/dev/null \
  | sed -n 's/^ *[0-9]*) \([0-9A-F]*\) "\(Developer ID Application:.*\)"$/\1 \2/p')"

if [ -n "${SIGN_IDENTITY:-}" ]; then
  # A caller who named an identity is releasing. Falling back to ad-hoc here
  # would hand them a bundle that cannot be notarised, after the point where
  # anyone would think to check.
  matched="$(security find-identity -v -p codesigning 2>/dev/null \
    | grep -F -- "$SIGN_IDENTITY" | head -n 1)"
  if [ -z "$matched" ]; then
    echo "build-app.sh: SIGN_IDENTITY=$SIGN_IDENTITY is not in the keychain" >&2
    echo "  available:" >&2
    security find-identity -v -p codesigning >&2
    exit 1
  fi
  chosen="$SIGN_IDENTITY"
  # Report the certificate's name, not the SHA-1 the caller may have passed:
  # "signed with 388391D0…" tells whoever reads the log nothing about whether
  # the right certificate was used.
  description="$(printf '%s\n' "$matched" | sed -n 's/.*"\(.*\)"$/\1/p')"
  case "$description" in
    "Developer ID Application:"*) ;;
    # Not fatal — an override is sometimes a deliberate experiment — but it
    # must not be reported as something it is not. Only a Developer ID
    # Application certificate notarises.
    *)
      echo "build-app.sh: $description is not a Developer ID Application" >&2
      echo "  certificate. The bundle will not notarise." >&2
      ;;
  esac
elif [ -n "$identities" ]; then
  chosen="$(printf '%s\n' "$identities" | head -n 1 | cut -d' ' -f1)"
  description="$(printf '%s\n' "$identities" | head -n 1 | cut -d' ' -f2-)"
  if [ "$(printf '%s\n' "$identities" | wc -l | tr -d ' ')" != "1" ]; then
    echo "build-app.sh: more than one Developer ID Application certificate;" >&2
    echo "  using $description" >&2
    echo "  set SIGN_IDENTITY to a SHA-1 from this list to choose another:" >&2
    printf '    %s\n' "$identities" >&2
  fi
else
  chosen=""
fi

if [ -n "$chosen" ]; then
  # --options runtime: the hardened runtime, which notarisation requires. It
  # is not optional and cannot be added after the fact — a bundle signed
  # without it is rejected by the notary service, not by codesign, so the
  # mistake surfaces minutes later at the end of an upload.
  #
  # --timestamp: a signature with no trusted timestamp stops verifying the day
  # the certificate expires, which would strand every copy already downloaded.
  # It needs to reach timestamp.apple.com, so this path is the one that fails
  # offline — deliberately, because an untimestamped release is worse.
  codesign --force --options runtime --timestamp \
    --sign "$chosen" "$DEST"
  echo "Signed with: $description"
else
  # --options runtime here too, so the bundle a contributor runs is subject to
  # the same restrictions as the one that ships. Library validation and the
  # rest are what the hardened runtime turns on, and finding out that they
  # break something at notarisation time — on a release branch, from an error
  # the notary service words vaguely — is how a day disappears.
  #
  # --timestamp=none because there is no certificate to timestamp: codesign
  # ignores --timestamp for an ad-hoc signature anyway, and saying so
  # explicitly keeps a build with no network from reaching for one.
  codesign --force --options runtime --timestamp=none --sign - "$DEST"
  echo "Signed ad-hoc: no Developer ID Application certificate in the keychain."
  echo "  The app will work on this Mac. Gatekeeper will refuse it on any other."
  echo "  Releases must be signed and notarised — see CONTRIBUTING.md."
fi

# LaunchServices caches bundle metadata by mtime; without this a rebuilt app
# can keep being launched with the previous Info.plist.
touch "$DEST"

echo "Built $DEST"
