#!/usr/bin/env bash
#
# PreToolUse(Bash) hook: propagate Claude Code's bypass-permissions mode to the
# delegated agent.
#
# Why: when the user runs Claude Code with permissions bypassed (`--dangerously-skip-permissions`
# or the interactive bypassPermissions mode), they have already granted unattended tool use.
# Headless `agy` without `--yolo` does the opposite of what they asked: it soft-denies or
# scratch-diverts the write and still reports success, so the workspace is untouched
# (issue #10). This hook adds `--yolo` to `agy-delegate` / `agy-job start` calls in that mode.
#
# It only INHERITS a grant the host already has: it never escalates a session that is still
# prompting, and it never returns a permissionDecision (Claude Code's own gate still applies).
# `--no-yolo` (or an explicit `--yolo`) on the command is respected untouched.
#
# Claude Code exposes no env var for the permission mode, so the mode is read from the hook
# payload (`.permission_mode`) and handed to the wrapper as an argument.
#
# The wrapper token may be quoted and may contain spaces (native Windows names it by quoted
# absolute path, ADR-0003), so `--yolo` goes in after the closing quote, never inside it.
#
# Toggle off via plugin userConfig `auto_yolo` (env CLAUDE_PLUGIN_OPTION_AUTO_YOLO:
# off / false / 0 / no / disabled). Default: on.
#
# Fails OPEN (no rewrite) on anything unexpected: exit 0 with no stdout.
#
set -uo pipefail

raw="$(printf '%s' "${CLAUDE_PLUGIN_OPTION_AUTO_YOLO:-on}" | tr '[:upper:]' '[:lower:]' | tr -d '[:space:]')"
case "$raw" in off|false|0|no|disabled) exit 0 ;; esac

IN="$(cat 2>/dev/null || true)"
[ -n "$IN" ] || exit 0

# Fast path: this hook fires on every Bash call, so skip Python unless the payload even
# mentions the wrapper (a cheap string test, no JSON semantics needed).
case "$IN" in *agy-delegate*|*agy-job*) ;; *) exit 0 ;; esac

. "$(dirname "$0")/../scripts/find-python.sh"
find_python || exit 0

AGY_HOOK_INPUT="$IN" "${PY[@]}" - <<'PY' 2>/dev/null || exit 0
import json, os, re, sys

try:
    d = json.loads(os.environ.get("AGY_HOOK_INPUT", ""))
except Exception:
    sys.exit(0)                                    # unparseable -> no rewrite

if d.get("tool_name") != "Bash":
    sys.exit(0)
if d.get("permission_mode") != "bypassPermissions":
    sys.exit(0)

cmd = d.get("tool_input", {}).get("command", "")
if not isinstance(cmd, str) or not cmd.strip():
    sys.exit(0)

# already decided explicitly? leave it alone
if re.search(r"(?<![\w-])--(?:no-)?yolo(?![\w-])", cmd):
    sys.exit(0)

# the wrapper at the start of the command or of a pipeline segment: a double-quoted,
# single-quoted or bare path token. Quoted forms may hold spaces.
m = re.search(
    r"""(?:^|\|)\s*("(?:[^"]*/)?agy-(delegate|job)(?:\.sh)?"|'(?:[^']*/)?agy-(delegate|job)(?:\.sh)?'|(?:[^\s|"']*/)?agy-(delegate|job)(?:\.sh)?(?![\w.-]))""",
    cmd)
if not m:
    sys.exit(0)

insert_at = m.end(1)
if (m.group(2) or m.group(3) or m.group(4)) == "job":
    # only `agy-job start ...` forwards options to the wrapper; status/result/cancel don't
    nxt = re.match(r"\s+(\w[\w-]*)", cmd[insert_at:])
    if not nxt or nxt.group(1) != "start":
        sys.exit(0)
    insert_at += nxt.end()

tool_input = dict(d.get("tool_input", {}))
tool_input["command"] = cmd[:insert_at] + " --yolo" + cmd[insert_at:]

print(json.dumps({
    "hookSpecificOutput": {
        "hookEventName": "PreToolUse",
        "updatedInput": tool_input,
        # surfaced with the permission decision, so the inheritance is never silent
        "permissionDecisionReason": "[antigravity] added --yolo: this session runs in bypassPermissions mode, and headless agy silently no-ops writes without it. Disable via the auto_yolo plugin option, or pass --no-yolo.",
    }
}))
PY
exit 0
