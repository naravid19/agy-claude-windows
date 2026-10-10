#!/usr/bin/env bash
#
# run-section.sh — run ONE section of tests/run-tests.sh, or list the sections.
#
#   bash tests/run-section.sh --list
#   bash tests/run-section.sh "skill structure"      # case-insensitive substring of the heading
#
# The full suite takes minutes; this takes the suite's setup (stubs, helpers, shared
# variables) plus the matching `echo "== ... =="` section(s). A section that leans on a
# helper defined in an earlier section (gate_rc, order_case, ...) fails here with
# `command not found`: run the full suite for those. Exit: 0 pass, 1 a check failed, 2 usage
# or no such section.
#
# The suite is read from a copy, so editing tests/run-tests.sh while this runs is safe.
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUITE="$HERE/run-tests.sh"

case "${1:-}" in
  ""|-h|--help) sed -n '3,12p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  --list) grep '^echo "== ' "$SUITE" | sed 's/^echo "== //; s/ ==".*$//'; exit 0 ;;
esac

PATTERN="$1"
# awk, not grep -iF: grep aborts on the multibyte dashes in some headings (Git Bash)
if ! awk -v pat="$PATTERN" '/^echo "== / && index(tolower($0), tolower(pat)) { f = 1 } END { exit !f }' "$SUITE"; then
  echo "run-section: no section matches '$PATTERN' (bash tests/run-section.sh --list)" >&2
  exit 2
fi

COPY="$(mktemp "${TMPDIR:-/tmp}/run-section.XXXXXX")" || exit 2
trap 'rm -f "$COPY"' EXIT
FIRST="$(grep -n '^echo "== ' "$SUITE" | head -1 | cut -d: -f1)"
{
  # setup, with HERE pinned: the copy does not live in tests/
  sed -n "1,$((FIRST - 1))p" "$SUITE" | sed "s|^HERE=.*|HERE=\"$HERE\"|"
  # shared variables that later sections assign at top level
  grep -E '^(HOOKS|BIN)=' "$SUITE"
  # the matching section(s), up to the next heading or the suite's summary
  awk -v pat="$PATTERN" '
    /^echo "== /  { on = (index(tolower($0), tolower(pat)) > 0) }
    /^if \[ "\$SKIP" -gt 0 \]/ { exit }
    on
  ' "$SUITE"
  echo 'echo ""; echo "PASS=$PASS FAIL=$FAIL"; [ "$FAIL" -eq 0 ]'
} > "$COPY"

bash "$COPY"
