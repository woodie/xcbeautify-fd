#!/bin/bash
set -e

# Wraps the xcodebuild -only-testing: dance from docs/DEVELOPMENT.md's "Test"
# section -- SwiftPM's own `swift test --filter` can't isolate a single Quick
# spec class (Quick generates test methods dynamically at runtime; see that
# doc for why `--filter` silently matches zero tests instead). No xcodegen
# step needed here, unlike the NextCaltrain sibling's test.sh -- xcodebuild
# already drives a bare Package.swift directly (Xcode 11+), and there's no
# simulator to boot since this runs on platform=macOS, not iOS.
#
#   ./test.sh                                         # full run, all specs
#   ./test.sh EngineSpec                              # one spec class
#   ./test.sh Tests/XctidyKitTests/EngineSpec.swift   # tab-completed path
#   ./test.sh XctidyKitTests/EngineSpec/some_example  # exact xcodebuild filter
#   ./test.sh -only-testing:XctidyKitTests/EngineSpec # forwarded as-is
#
# If you've copied this file into your own SwiftPM package, the four
# variables below are the only things you should need to change -- nothing
# in the logic past this point is xctidy-specific.

SCHEME="${SCHEME:-xctidy}"
DESTINATION="${DESTINATION:-platform=macOS}"
TEST_TARGET="${TEST_TARGET:-XctidyKitTests}"
XCTIDY_BIN="${XCTIDY_BIN:-xctidy}"

SPECS_DIR="$(dirname "$0")/Tests/$TEST_TARGET"

if ! command -v "$XCTIDY_BIN" &> /dev/null; then
  echo "error: '$XCTIDY_BIN' not found on PATH -- run 'make install' first" >&2
  exit 1
fi

# A bare class name or a tab-completed ".swift" path is wrapped as
# $TEST_TARGET/<name> unless it already contains a "/" (already
# Target/Class or Target/Class/method). Anything dash-prefixed (already an
# xcodebuild flag) or no argument at all is forwarded unchanged -- see the
# NextCaltrain sibling's test.sh for the same convention.
ARGS=("$@")
if [ "$#" -gt 0 ] && [[ "$1" != -* ]]; then
  ARG="$1"
  [[ "$ARG" == *.swift ]] && ARG="$(basename "$ARG" .swift)"
  case "$ARG" in
    */*) FILTER="-only-testing:$ARG" ;;
    *)   FILTER="-only-testing:$TEST_TARGET/$ARG" ;;
  esac
  ARGS=("$FILTER" "${@:2}")
fi

xcodebuild test \
  -scheme "$SCHEME" \
  -destination "$DESTINATION" \
  -enableCodeCoverage NO \
  "${ARGS[@]}" \
  | "$XCTIDY_BIN" "$SPECS_DIR"
