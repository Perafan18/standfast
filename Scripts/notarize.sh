#!/bin/bash
# Submits Standfast.app to Apple's notary service, staples the ticket to it,
# and proves the result is what a user downloading it will get.
#
# Separate from build-app.sh because the two have different costs and
# different audiences. Building is free, offline, and every contributor does
# it. Notarising uploads to Apple, takes minutes, and needs credentials only
# the release manager has — running it from the build script would make every
# `make app` either slow or broken.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/.."

APP="${APP:-.build/Standfast.app}"

fail() {
  echo "notarize.sh: $*" >&2
  exit 1
}

[ -d "$APP" ] || fail "$APP does not exist; run ./Scripts/build-app.sh first"

# Checked here rather than discovered at the end of an upload. The notary
# service accepts the submission, spends several minutes on it and *then*
# reports `Invalid` with a status log that has to be fetched separately — so
# every condition that can be read off the local bundle is read off it first.
echo "==> Checking the signature before spending an upload on it"
signature="$(codesign -dvvv "$APP" 2>&1 || true)"

case "$signature" in
  *"Authority=Developer ID Application:"*) ;;
  *)
    echo "  the bundle is not signed with a Developer ID Application" >&2
    echo "  certificate. Apple notarises nothing else — an ad-hoc, Apple" >&2
    echo "  Development or Apple Distribution signature is rejected." >&2
    echo "" >&2
    echo "  Install a Developer ID Application certificate, then:" >&2
    echo "    ./Scripts/build-app.sh" >&2
    fail "nothing to notarise"
    ;;
esac

# The hardened runtime is a notarisation requirement, and the only signal that
# it is missing is a rejection after the fact.
#
# Read off the flags field rather than the whole of codesign's output: the word
# "runtime" appears in it for other reasons, and a check that matches those
# passes a bundle that has no hardened runtime at all.
flags="$(printf '%s\n' "$signature" | sed -n 's/.*flags=\([^ ]*\).*/\1/p')"
case "$flags" in
  *runtime*) ;;
  *) fail "the bundle is not signed with the hardened runtime (--options runtime)" ;;
esac

# A signature with no trusted timestamp is also refused, and for a reason worth
# keeping: without one the signature stops verifying when the certificate
# expires, on copies already downloaded.
case "$signature" in
  *Timestamp=*) ;;
  *) fail "the signature has no secure timestamp (--timestamp)" ;;
esac

# The leaf only. `Developer ID Certification Authority` is the intermediate and
# matches any pattern loose enough to be convenient here.
echo "    $(printf '%s\n' "$signature" \
  | sed -n 's/^Authority=\(Developer ID Application:.*\)/\1/p')"

# Credentials, and why they are read rather than asked for.
#
# `notarytool` takes either a keychain profile or the three values that make
# one. A profile is the better path — the app-specific password is then stored
# by macOS instead of living in a shell history, a CI log or this repository —
# so it is tried first, and the environment is the fallback for a machine
# where storing one is not possible.
#
# Nothing here prompts. A script that stops to ask for a password cannot be
# run unattended, and an app-specific password typed at a prompt is one that
# ends up pasted into a terminal scrollback.
PROFILE="${NOTARY_PROFILE:-standfast-notary}"

if [ -n "${NOTARY_KEY:-}" ] && [ -n "${NOTARY_KEY_ID:-}" ] \
  && [ -n "${NOTARY_ISSUER:-}" ]; then
  # An App Store Connect API key, and the only path that needs no interactive
  # Apple account behind it — which is what makes it the one CI can use. It is
  # also the credential this team already has, minted for uploading iOS builds;
  # notarytool takes the same key.
  echo "==> Using the App Store Connect API key from the environment"
  credentials=(
    --key "$NOTARY_KEY"
    --key-id "$NOTARY_KEY_ID"
    --issuer "$NOTARY_ISSUER"
  )
elif xcrun notarytool history --keychain-profile "$PROFILE" >/dev/null 2>&1; then
  echo "==> Using the keychain profile '$PROFILE'"
  credentials=(--keychain-profile "$PROFILE")
elif [ -n "${APPLE_ID:-}" ] && [ -n "${TEAM_ID:-}" ] \
  && [ -n "${APP_SPECIFIC_PASSWORD:-}" ]; then
  echo "==> Using APPLE_ID / TEAM_ID / APP_SPECIFIC_PASSWORD from the environment"
  credentials=(
    --apple-id "$APPLE_ID"
    --team-id "$TEAM_ID"
    --password "$APP_SPECIFIC_PASSWORD"
  )
else
  # Everything needed to fix this, in the message, rather than "authentication
  # failed". The app-specific password is not the Apple ID password and is not
  # obtainable from this machine: it is minted at appleid.apple.com.
  cat >&2 <<EOF
notarize.sh: no notarisation credentials.

  Store them once, and every later release picks them up with no arguments:

    xcrun notarytool store-credentials "$PROFILE" \\
      --apple-id "<your-apple-id-email>" \\
      --team-id "<your-10-character-team-id>" \\
      --password "<an-app-specific-password>"

  The password is an *app-specific* password, created at
  https://appleid.apple.com under Sign-In and Security. Your normal Apple ID
  password is refused. The team ID is the 10 characters in brackets after your
  name in:

    security find-identity -v -p codesigning

  Or, for a machine where no keychain profile can be stored, export
  APPLE_ID, TEAM_ID and APP_SPECIFIC_PASSWORD instead.

  For CI, prefer an App Store Connect API key over either: it needs no
  interactive Apple account and nothing is stored on the machine. Export
  NOTARY_KEY (path to the AuthKey_XXXX.p8), NOTARY_KEY_ID and NOTARY_ISSUER.
  The key is minted at App Store Connect -> Users and Access -> Integrations,
  and the same key that uploads builds also notarises.
EOF
  exit 1
fi

# ditto, not `zip`. The notary service reads a bundle out of the archive, and
# `zip` does not preserve symlinks or extended attributes — a bundle that goes
# through it can arrive with its signature broken, which is reported as an
# invalid submission rather than as a bad archive.
ZIP="$(mktemp -d)/Standfast.zip"
trap 'rm -rf "$(dirname "$ZIP")"' EXIT

echo "==> Packing the bundle for upload"
ditto -c -k --keepParent "$APP" "$ZIP"

# --wait, so the exit status means something. Without it the command returns as
# soon as the upload finishes and a failed notarisation looks like a success.
echo "==> Submitting to Apple (this takes minutes, not seconds)"
if ! xcrun notarytool submit "$ZIP" "${credentials[@]}" --wait; then
  echo "" >&2
  echo "  Notarisation failed. The reason is in the log, not in the output" >&2
  echo "  above — fetch it with the submission id printed there:" >&2
  echo "    xcrun notarytool log <submission-id> --keychain-profile $PROFILE" >&2
  exit 1
fi

# Stapling writes the ticket into the bundle so Gatekeeper can verify it with
# no network. Without it a user who is offline, or behind something that
# blocks Apple, sees the app refused even though it was notarised.
echo "==> Stapling the ticket"
xcrun stapler staple "$APP"

echo "==> Verifying what a downloader will actually get"
codesign --verify --deep --strict --verbose=2 "$APP"
xcrun stapler validate "$APP"
# `-t install` is the assessment Gatekeeper makes for an app being opened for
# the first time. `--assess` on its own defaults to the execute rule, which is
# not the one that rejects a quarantined download.
spctl --assess --type install -vv "$APP"

echo "Notarised and stapled $APP"
