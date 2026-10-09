#!/usr/bin/env bash
#
# SessionStart hook: inject this plugin's COST-AWARE routing policy as session
# context, so the discipline (delegate above the break-even, keep Claude's context
# lean, always verify agy's output) applies even when the `antigravity` skill isn't
# explicitly invoked. Prints the hookSpecificOutput JSON on stdout.
#
# Toggle off via plugin userConfig `coding_policy` (env CLAUDE_PLUGIN_OPTION_CODING_POLICY:
# off / false / 0 / no / disabled). Default: on.
#
set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

raw="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_CODING_POLICY:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in
  off|false|0|no|disabled) exit 0 ;;
esac

# On native Windows no plugin bin/ is on the Bash tool's PATH (Claude Code bug), so the
# injected "Call:" line names the tool by absolute path; elsewhere it stays the bare name.
# The path is resolved here, not written as $CLAUDE_PLUGIN_ROOT, which model-run Bash lacks.
call="agy-delegate"
case "${OSTYPE:-}" in
  # Quoted (the path may hold spaces); the \" is the JSON escape, as this is spliced into a string.
  msys*|cygwin*|win32) call="\\\"$(cd "$HERE/.." && pwd)/bin/agy-delegate\\\"" ;;
esac
# bash 5.2 reads an unquoted `&` in a ${//} replacement as "the matched text"; a path may hold one.
shopt -u patsub_replacement 2>/dev/null
policy="$(cat "$HERE/policy-context.json")"
printf '%s
' "${policy//@@AGY_DELEGATE@@/$call}"
exit 0
