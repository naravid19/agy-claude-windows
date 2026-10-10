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
# Claude Code exposes no env var for the permission mode, so it is read from the hook
# payload (`.permission_mode`).
#
# The command line is split the way a shell would: quotes group a word, and an unquoted
# `| & ; ( )` or newline starts a new command. So the wrapper is found in command position
# wherever it sits (`cd d && agy-delegate ...`, `FOO=1 agy-delegate ...`, a pipeline, a
# subshell), text inside quotes is never mistaken for a command or a flag, and a wrapper
# named by a quoted absolute path with spaces (native Windows, ADR-0003) gets `--yolo`
# after the closing quote. Not covered, by design: `bash -c "agy-delegate ..."` (the call
# stays unapproved, the same as before this hook existed).
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

SEPARATORS = "|&;()\n"
PREFIXES = ("time", "exec", "nohup", "command")      # may precede a command without being one
WRAPPER = re.compile(r"(?:.*/)?agy-(delegate|job)(?:\.sh)?")
ASSIGNMENT = re.compile(r"[A-Za-z_]\w*=")


def split_commands(cmd):
    """Split into commands of words, each word (text, start, end) with quotes removed from
    text. Returns None on an unbalanced quote. Stops at an unquoted `<<`: what follows is
    heredoc body, not commands."""
    cmds, i, n = [[]], 0, len(cmd)
    while i < n:
        c = cmd[i]
        if c in SEPARATORS:
            if cmds[-1]:
                cmds.append([])
            i += 1
        elif c in " \t":
            i += 1
        else:
            start, text = i, ""
            while i < n and cmd[i] not in " \t" and cmd[i] not in SEPARATORS:
                c = cmd[i]
                if c in "\"'":
                    j = i + 1
                    while j < n and cmd[j] != c:
                        j += 2 if (c == '"' and cmd[j] == "\\") else 1
                    if j >= n:
                        return None
                    text += cmd[i + 1:j]
                    i = j + 1
                elif c == "\\" and i + 1 < n:
                    text += cmd[i + 1]
                    i += 2
                else:
                    text += c
                    i += 1
            if text.startswith("<<") and not text.startswith("<<<"):
                break
            cmds[-1].append((text, start, i))
    return cmds


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

cmds = split_commands(cmd)
if cmds is None:
    sys.exit(0)

inserts = []
for words in cmds:
    k = 0
    while k < len(words) and (ASSIGNMENT.match(words[k][0]) or words[k][0] in PREFIXES):
        k += 1
    if k >= len(words):
        continue
    m = WRAPPER.fullmatch(words[k][0])
    if not m:
        continue
    rest = words[k + 1:]
    after = words[k][2]
    if m.group(1) == "job":
        # only `agy-job start ...` forwards options to the wrapper; status/result/cancel don't
        if not rest or rest[0][0] != "start":
            continue
        after = rest[0][2]
    # already decided explicitly? leave that call alone
    if any(w[0] in ("--yolo", "--no-yolo") for w in rest):
        continue
    inserts.append(after)

if not inserts:
    sys.exit(0)

new_cmd = cmd
for pos in sorted(inserts, reverse=True):
    new_cmd = new_cmd[:pos] + " --yolo" + new_cmd[pos:]
tool_input = dict(d.get("tool_input", {}))
tool_input["command"] = new_cmd

print(json.dumps({"hookSpecificOutput": {"hookEventName": "PreToolUse", "updatedInput": tool_input}}))
PY
exit 0
