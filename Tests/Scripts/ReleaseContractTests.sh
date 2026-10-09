#!/bin/bash
# What the release workflow must keep being true.
#
# It cannot be run here — it needs a Developer ID certificate, Apple's notary
# service, and the self-hosted Mac — so every one of these assertions reads the
# file instead. That is a weaker test than executing it, and it is the strongest
# one available: each assertion below corresponds to a defect that was found by
# reading, would have produced a green check, and would have produced no
# release.
set -euo pipefail

cd "$(dirname "${BASH_SOURCE[0]}")/../.."
WORKFLOW=.github/workflows/release.yml

failures=0

fail() {
  printf 'FAIL: %s\n' "$1" >&2
  failures=$((failures + 1))
}

pass() { printf 'PASS: %s\n' "$1"; }

# 1 ────────────────────────────────────────────────────────────────────────────
# The job rewrites the keychain search list, which is machine-wide state on a
# persistent Mac. Keying concurrency on the ref lets a tag and a manual run —
# or two tags — overlap and fight over it.
concurrency="$(awk '/^concurrency:/ { found = 1; next }
  found && /^[^[:space:]]/ { exit }
  found && /group:/ { print; exit }' "$WORKFLOW")"
if printf '%s' "$concurrency" | grep -q 'github.ref'; then
  fail "concurrency is keyed on github.ref, so two runs can rewrite the host keychain at once"
elif [ -z "$concurrency" ]; then
  fail "the workflow declares no concurrency group at all"
else
  pass "concurrency serialises every run on the host, whatever triggered it"
fi

# 2 ────────────────────────────────────────────────────────────────────────────
# Every secret the job consumes has to be in the gate. Checking three of five
# meant a run could pass the gate and then fail at notarisation, after the
# certificate was already imported into the host keychain.
gate="$(awk '/id: gate/ { found = 1 }
  found && /- name:/ && !/Are the signing secrets/ { exit }
  found { print }' "$WORKFLOW")"
# Both halves, because either alone is satisfied by a gate that cannot work.
# A name left in the loop with no `env` binding behind it reads an empty
# variable and reports a configured secret as missing — the reverse of the bug,
# and just as fatal to a release.
gate_env="$(printf '%s' "$gate" | awk '/env:/ { inside = 1; next }
  inside && /run:/ { exit } inside { print }')"
gate_run="$(printf '%s' "$gate" | awk '/run:/ { inside = 1; next } inside { print }')"
bound=0
for secret in DEVELOPER_ID_P12_BASE64 DEVELOPER_ID_P12_PASSWORD KEYCHAIN_PASSWORD \
  ASC_KEY_ID ASC_ISSUER_ID ASC_KEY_P8_BASE64; do
  printf '%s' "$gate_env" | grep -qF "$secret: \${{ secrets.$secret }}" \
    || { fail "the gate never binds $secret from repository secrets"; bound=1; }
  printf '%s' "$gate_run" | grep -qF "$secret" \
    || { fail "the gate binds $secret but never tests whether it is empty"; bound=1; }
done
[ "$bound" -eq 0 ] && pass "the gate binds and tests every secret the job goes on to use"

# 3 ────────────────────────────────────────────────────────────────────────────
# A tag is a publication. Skipping green on one produces a check that says the
# release succeeded and a repository with no artifact in it — the exact shape
# of a failure nobody notices until somebody tries to download it.
if ! printf '%s' "$gate" | grep -q 'refs/tags'; then
  fail "the gate treats a tag the same as a manual run; a tag with no secrets must fail"
else
  pass "a tag with missing secrets fails instead of skipping green"
fi

# 4 ────────────────────────────────────────────────────────────────────────────
# Pushing a tag does not create a GitHub Release. `gh release upload` against
# one that does not exist fails, and it failed at the last step of the job,
# after signing and notarising.
if ! grep -q 'gh release create' "$WORKFLOW"; then
  fail "nothing creates the GitHub Release that the upload step uploads to"
else
  pass "the workflow creates the release it uploads to"
fi

# 5 ────────────────────────────────────────────────────────────────────────────
# `gh` reads GH_TOKEN. Without it the step fails on authentication, again at
# the very end.
upload="$(awk '/- name: Attach the app to the release/ { found = 1 }
  found && /- name: Put the machine back/ { exit }
  found { print }' "$WORKFLOW")"
if ! printf '%s' "$upload" | grep -q 'GH_TOKEN'; then
  fail "the release step calls gh without declaring GH_TOKEN"
else
  pass "the release step gives gh a token"
fi

# 6 ────────────────────────────────────────────────────────────────────────────
# A manual run is the smoke test for this whole rail. One that signs, notarises
# and then throws the result away proves the steps ran and leaves nothing to
# inspect.
if ! grep -q 'upload-artifact' "$WORKFLOW"; then
  fail "a manual run keeps no artifact, so the smoke test proves nothing afterwards"
else
  pass "a manual run leaves the signed app behind as a workflow artifact"
fi

# The step named "$1", up to the next step.
step_block() {
  awk -v name="- name: $1" '
    !found && index($0, name) { found = 1; next }
    found && /^      - / { exit }
    found { print }' "$WORKFLOW"
}

# Its `run: |` body, dedented, so the test can execute it rather than read it.
step_script() {
  step_block "$1" | awk '
    /^        run: \|$/ { inside = 1; next }
    inside && /^          / { print substr($0, 11); next }
    inside && NF { exit }
    inside { print "" }'
}

line_of() { { grep -nF -- "$1" "$WORKFLOW" || true; } | head -n 1 | cut -d: -f1; }

# 7 ────────────────────────────────────────────────────────────────────────────
# The runner is Apple silicon and SwiftPM builds only the host's slice unless
# asked, so an Intel Mac on macOS 14 would be refused the notarised download.
build_step="$(step_block "Build and sign")"
build_archs="$(printf '%s\n' "$build_step" | grep -E '^ +ARCHS:' || true)"
case "$build_archs" in
  *arm64*x86_64* | *x86_64*arm64*) pass "the release is built for both architectures" ;;
  *) fail "Build and sign does not ask build-app.sh for arm64 and x86_64" ;;
esac

slices_step="Both architectures are in the executable"
slices_line="$(line_of "- name: $slices_step")"
if [ -z "$slices_line" ] \
  || [ "$slices_line" -lt "$(line_of "- name: Build and sign")" ] \
  || [ "$slices_line" -gt "$(line_of "- name: Notarise and staple")" ]; then
  fail "nothing checks the executable's slices between building and notarising"
else
  slices_dir="$(mktemp -d "${TMPDIR:-/tmp}/standfast-release-slices.XXXXXX")"
  step_script "$slices_step" > "$slices_dir/check.sh"
  mkdir -p "$slices_dir/bin"
  # shellcheck disable=SC2016 # Expands when the fake runs.
  printf '%s\n' '#!/bin/bash' 'echo "$STANDFAST_FAKE_ARCHS"' > "$slices_dir/bin/lipo"
  chmod +x "$slices_dir/bin/lipo"
  for thin in arm64 x86_64; do
    if PATH="$slices_dir/bin:$PATH" STANDFAST_FAKE_ARCHS="$thin" \
      bash "$slices_dir/check.sh" >/dev/null 2>&1; then
      fail "the slice check accepts an executable that is only $thin"
    fi
  done
  if PATH="$slices_dir/bin:$PATH" STANDFAST_FAKE_ARCHS="x86_64 arm64" \
    bash "$slices_dir/check.sh" >/dev/null 2>&1; then
    pass "the slice check refuses a thin executable and accepts a universal one"
  else
    fail "the slice check refuses a universal executable"
  fi
  rm -rf "$slices_dir"
fi

# 8 ────────────────────────────────────────────────────────────────────────────
# A tag pushed before the version bump publishes a release whose app reports
# the previous version. Checked before the gate, so a mismatch fails before the
# job touches the host keychain.
tag_step="The tag names the version the app reports"
tag_line="$(line_of "- name: $tag_step")"
if [ -z "$tag_line" ] || [ "$tag_line" -gt "$(line_of "id: gate")" ]; then
  fail "nothing compares the tag with Info.plist before the signing gate"
elif ! step_block "$tag_step" | grep -qF "if: startsWith(github.ref, 'refs/tags/')"; then
  fail "the tag check is not limited to tags, so a manual run from a branch fails it"
else
  tag_dir="$(mktemp -d "${TMPDIR:-/tmp}/standfast-release-tag.XXXXXX")"
  step_script "$tag_step" > "$tag_dir/check.sh"
  mkdir -p "$tag_dir/Resources"
  /usr/libexec/PlistBuddy -c 'Add :CFBundleShortVersionString string 1.4.0' \
    "$tag_dir/Resources/Info.plist" >/dev/null
  run_tag_check() {
    (cd "$tag_dir" && GITHUB_REF_NAME="$1" bash check.sh >/dev/null 2>&1)
  }
  if run_tag_check v1.3.9; then
    fail "the tag check publishes v1.3.9 from a bundle that says 1.4.0"
  elif ! run_tag_check v1.4.0; then
    fail "the tag check refuses v1.4.0 for a bundle that says 1.4.0"
  else
    pass "a tag that disagrees with Info.plist fails before anything is signed"
  fi
  rm -rf "$tag_dir"
fi

# ─────────────────────────────────────────────────────────────────────────────
if [ "$failures" -ne 0 ]; then
  printf '\n%s release contract assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll release contract assertions passed\n'
