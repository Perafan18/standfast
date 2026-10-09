#!/bin/bash
# What build-app.sh must do with whatever SwiftPM hands it.
#
# The real script runs against fake `swift`, `codesign` and `security`: no
# compiler runs, and nothing reads or signs with this Mac's keychain.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../.." && pwd)"
BUILD_APP="$ROOT/Scripts/build-app.sh"
TEST_TMP="$(mktemp -d "${TMPDIR:-/tmp}/standfast-build-app.XXXXXX")"
trap 'rm -rf "$TEST_TMP"' EXIT

FAKE_BIN="$TEST_TMP/bin"
mkdir -p "$FAKE_BIN"
# shellcheck disable=SC2016 # Variables expand when the generated fake runs.
printf '%s\n' \
  '#!/bin/bash' \
  'printf "%s\n" "$*" >> "$STANDFAST_FAKE_SWIFT_LOG"' \
  'case " $* " in' \
  '  *" --show-bin-path "*) echo "$STANDFAST_FAKE_PRODUCTS" ;;' \
  'esac' \
  'exit 0' > "$FAKE_BIN/swift"
printf '%s\n' '#!/bin/bash' 'exit 0' > "$FAKE_BIN/codesign"
printf '%s\n' '#!/bin/bash' 'echo "     0 valid identities found"' 'exit 0' \
  > "$FAKE_BIN/security"
chmod +x "$FAKE_BIN/swift" "$FAKE_BIN/codesign" "$FAKE_BIN/security"

failures=0
case_count=0
case_name=""
case_dir=""

fail() {
  printf 'FAIL: %s — %s\n' "$case_name" "$1" >&2
  failures=$((failures + 1))
}

pass() { printf 'PASS: %s — %s\n' "$case_name" "$1"; }

# A products directory holding an executable and a resource bundle whose
# catalogues sit under `$catalogue_root` inside it.
begin_case() {
  case_name="$1"
  local catalogue_root="$2"
  case_count=$((case_count + 1))
  case_dir="$TEST_TMP/case-$case_count"
  local bundle="$case_dir/products/Standfast_Standfast.bundle"
  mkdir -p "$case_dir/products"
  printf 'executable\n' > "$case_dir/products/Standfast"
  for language in en es; do
    mkdir -p "$bundle/$catalogue_root$language.lproj"
    printf '"menu.start" = "%s";\n' "$language" \
      > "$bundle/$catalogue_root$language.lproj/Localizable.strings"
  done
}

# Through `env` so per-case assignments passed in "$@" stay assignments, and
# without the caller's own ARCHS or sandbox choice leaking into a default case.
run_build_app() {
  env -u ARCHS -u STANDFAST_SWIFTPM_SANDBOX \
    PATH="$FAKE_BIN:$PATH" \
    DEST="$case_dir/Standfast.app" \
    SIGN_IDENTITY=- \
    STANDFAST_FAKE_PRODUCTS="$case_dir/products" \
    STANDFAST_FAKE_SWIFT_LOG="$case_dir/swift.log" \
    "$@" \
    "$BUILD_APP" > "$case_dir/output" 2>&1
}

expect_catalogues_packaged() {
  local resources="$case_dir/Standfast.app/Contents/Resources"
  local missing=""
  for language in en es; do
    grep -Fq "\"$language\"" "$resources/$language.lproj/Localizable.strings" \
      2>/dev/null || missing="$missing $language"
  done
  if [ -n "$missing" ]; then
    fail "no loose .lproj in Contents/Resources for:$missing"
  else
    pass "both loose .lproj land in Contents/Resources"
  fi
  if [ -d "$resources/Standfast_Standfast.bundle" ]; then
    pass "the SwiftPM bundle lands in Contents/Resources"
  else
    fail "the SwiftPM bundle is not in Contents/Resources"
  fi
}

# ---------------------------------------------------------------------------

begin_case "native build system, catalogues flat in the bundle" ""
if run_build_app; then
  expect_catalogues_packaged
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

# Swift Build, the default from Swift 6.4, emits a real macOS bundle.
begin_case "Swift Build, catalogues under Contents/Resources" "Contents/Resources/"
if run_build_app; then
  expect_catalogues_packaged
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

compile_line() { grep -F -- '--product Standfast' "$case_dir/swift.log" || true; }

# Homebrew already runs the build under sandbox-exec, and macOS refuses the
# nested one SwiftPM applies to manifest evaluation.
begin_case "STANDFAST_SWIFTPM_SANDBOX=0, as the formula sets it" "Contents/Resources/"
if run_build_app STANDFAST_SWIFTPM_SANDBOX=0; then
  case " $(compile_line) " in
    *" --disable-sandbox "*) pass "the compile runs without SwiftPM's own sandbox" ;;
    *) fail "the compile still asks for SwiftPM's sandbox: $(compile_line)" ;;
  esac
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

begin_case "SwiftPM's sandbox by default" "Contents/Resources/"
if run_build_app; then
  if grep -Fq -- '--disable-sandbox' "$case_dir/swift.log"; then
    fail "a contributor's build drops SwiftPM's sandbox nobody asked to drop"
  elif [ -z "$(compile_line)" ]; then
    fail "the fake swift never saw the compile"
  else
    pass "the sandbox stays on unless the caller turns it off"
  fi
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

bin_path_line() { grep -F -- '--show-bin-path' "$case_dir/swift.log" || true; }

# The bin path is asked with the same flags as the compile: the native build
# system puts a multi-arch product somewhere a host-only query does not name.
begin_case "ARCHS=\"arm64 x86_64\", as the release sets it" "Contents/Resources/"
if run_build_app ARCHS="arm64 x86_64"; then
  for call in compile bin_path; do
    case " $("${call}_line") " in
      *" --arch arm64 --arch x86_64 "*) pass "the $call call asks for both slices" ;;
      *) fail "the $call call does not ask for both slices: $("${call}_line")" ;;
    esac
  done
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

# Homebrew and a contributor's `make app` build only what their Mac runs.
begin_case "the host architecture by default" "Contents/Resources/"
if run_build_app; then
  if grep -Fq -- '--arch' "$case_dir/swift.log"; then
    fail "a build nobody asked to be universal names an architecture"
  else
    pass "no architecture is forced unless ARCHS asks for one"
  fi
else
  fail "build-app.sh failed: $(cat "$case_dir/output")"
fi

# ---------------------------------------------------------------------------
if [ "$failures" -ne 0 ]; then
  printf '\n%s build-app.sh contract assertion(s) failed\n' "$failures" >&2
  exit 1
fi
printf '\nAll build-app.sh contract assertions passed\n'
