# shellcheck shell=bash
#
# find-python.sh — sourced (not run) by every entrypoint and hook that needs Python.
#
# `command -v python3` does not prove there is a Python. A python.org install on
# Windows ships no python3.exe, so `python3` resolves to the Microsoft Store alias
# stub: it is on PATH, passes `command -v`, and exits 49 when run. So each candidate
# is judged by RUNNING it. The probe also requires Python 3, so a `python` that is
# 2.x (old Linux) is skipped rather than picked.
#
# find_python sets the array PY and returns 0, or empties it and returns 1. Call the
# result as "${PY[@]}" — `py -3` is two words. With a working python3 it is chosen
# first, exactly as before this existed.
PY_CANDIDATES="python3, python, py -3"
find_python() {
  local c
  for c in python3 python "py -3"; do
    # shellcheck disable=SC2086,SC2206  # unquoted on purpose: "py -3" is a command plus an argument
    if $c -c 'import sys; sys.exit(sys.version_info < (3,))' </dev/null >/dev/null 2>&1; then
      PY=($c); return 0
    fi
  done
  PY=(); return 1
}

# For entrypoints that cannot run without Python: resolve, or say which interpreters
# were tried and exit 16, the plugin's "no Python" code (docs/TROUBLESHOOTING.md).
need_python() { # $1 = the tool name that prefixes the message
  find_python && return 0
  echo "$1: no working Python 3 found (tried $PY_CANDIDATES) — install Python 3" >&2
  exit 16
}
