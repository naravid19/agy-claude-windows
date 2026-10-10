#!/usr/bin/env bash
#
# run-section.sh — run ONE section of tests/run-tests.sh, or list the sections.
#
#   bash tests/run-section.sh --list
#   bash tests/run-section.sh "skill structure"      # case-insensitive substring of the heading
#
# The full suite takes minutes; this runs the suite's setup (stubs, helpers, shared
# variables: everything above the `end of setup` marker) plus the matching `echo "== ... =="`
# section(s). A section that leans on a helper defined inside an earlier section (gate_rc,
# PROP, ...) cannot work alone: it is reported and exits 1, never passed. Exit: 0 pass,
# 1 a check failed or a helper was missing, 2 usage or no such section.
#
# The suite is read from a copy, so editing tests/run-tests.sh while this runs is safe.
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SUITE="${RUN_SECTION_SUITE:-$HERE/run-tests.sh}"   # the override is for the tests of this script
MARK='# --- end of setup'

case "${1:-}" in
  ""|-h|--help) sed -n '3,14p' "$0" | sed 's/^# \{0,1\}//'; exit 2 ;;
  --list) grep '^echo "== ' "$SUITE" | sed 's/^echo "== //; s/ ==".*$//'; exit 0 ;;
esac

# The pattern goes in through the environment: awk -v would eat a backslash in it.
export RUN_SECTION_PATTERN="$1" RUN_SECTION_HERE="$HERE"
# awk, not grep -iF: grep aborts on the multibyte dashes in some headings (Git Bash)
if ! awk '/^echo "== / && index(tolower($0), tolower(ENVIRON["RUN_SECTION_PATTERN"])) { f = 1 } END { exit !f }' "$SUITE"; then
  echo "run-section: no section matches '$1' (bash tests/run-section.sh --list)" >&2
  exit 2
fi
SETUP_END="$(grep -n "^$MARK" "$SUITE" | head -1 | cut -d: -f1)"
if [ -z "$SETUP_END" ]; then
  echo "run-section: the suite has no '$MARK' marker line" >&2
  exit 2
fi

COPY="$(mktemp "${TMPDIR:-/tmp}/run-section.XXXXXX")" || exit 2
ERRF="$(mktemp "${TMPDIR:-/tmp}/run-section.XXXXXX")" || exit 2
trap 'rm -f "$COPY" "$ERRF"' EXIT
{
  # setup, with HERE taken from the environment: the copy does not live in tests/, and a
  # path spliced into sed breaks on '&' and '|'
  sed -n "1,$((SETUP_END - 1))p" "$SUITE" | sed 's|^HERE=.*|HERE="$RUN_SECTION_HERE"|'
  # what the setup already counted is not this section's result
  echo 'SETUP_PASS=$PASS'
  # shared variables that later sections assign at top level
  grep -E '^(HOOKS|BIN)=' "$SUITE"
  # the matching section(s), up to the next heading or the suite's summary
  awk '
    /^echo "== /  { on = (index(tolower($0), tolower(ENVIRON["RUN_SECTION_PATTERN"])) > 0) }
    /^if \[ "\$SKIP" -gt 0 \]/ { exit }
    on
  ' "$SUITE"
  echo 'echo ""; echo "PASS=$((PASS - SETUP_PASS)) FAIL=$FAIL"; [ "$FAIL" -eq 0 ]'
} > "$COPY"

bash "$COPY" 2> "$ERRF"; rc=$?
cat "$ERRF" >&2
# A missing helper prints `command not found` and leaves FAIL untouched, so the run would
# read as green. Count it as the failure it is.
if grep -q ': command not found' "$ERRF"; then
  echo "run-section: this section needs a helper defined in an earlier section; run the full suite" >&2
  exit 1
fi
exit "$rc"
