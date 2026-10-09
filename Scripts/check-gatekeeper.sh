#!/bin/bash
# Gatekeeper's verdict on a packaged app, judged against how it was signed.
set -euo pipefail

if [ "$#" -ne 1 ]; then
  echo "usage: check-gatekeeper.sh APP" >&2
  exit 2
fi

APP="$1"

fail() {
  echo "FAIL: $*" >&2
  exit 1
}

signature="$(codesign -dvvv "$APP" 2>&1 || true)"
assessment="$(spctl --assess --type install -vv "$APP" 2>&1 || true)"
printf '    %s\n' "${assessment//$'\n'/$'\n    '}"

# Reported rather than asserted for an ad-hoc build, which is supposed to be
# rejected: failing on it would break every contributor and all of CI.
case "$signature" in
  *"Authority=Developer ID Application:"*)
    case "$assessment" in
      *accepted*) ;;
      *)
        # Gatekeeper denies every Developer ID build until it is notarised, so
        # that one rejection is the expected answer on the release manager's
        # Mac. Once stapled, nothing excuses one.
        if xcrun stapler validate "$APP" >/dev/null 2>&1; then
          fail "notarised, stapled, and still rejected by Gatekeeper"
        fi
        case "$assessment" in
          *"source=Unnotarized Developer ID"*)
            echo "    (Developer ID, not notarised yet: rejection here is expected;"
            echo "     notarize.sh asserts acceptance after stapling)" ;;
          *) fail "signed with a Developer ID and rejected by Gatekeeper" ;;
        esac ;;
    esac ;;
  *)
    echo "    (ad-hoc build: rejection here is expected)" ;;
esac
