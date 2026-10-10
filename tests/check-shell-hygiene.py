#!/usr/bin/env python3
"""Fail on two shell shapes that review kept finding in new code.

1. A temp file named from the PID (`"$CACHE.$$"`, `/tmp/x.$$`). In a shared temp dir the
   name is predictable, so another user can plant a symlink there and have the write follow
   it. Use `mktemp`, or `mkdir` for a lock.
2. `printf|echo|cat ... > file 2>/dev/null`. Redirections apply left to right, so the
   `2>/dev/null` comes too late to silence the error from opening `file`. Group it:
   `{ printf ... > file; } 2>/dev/null`.

A line carrying `# hygiene-ok: <reason>` is left alone. Exit: 0 clean, 1 found something,
2 nothing to scan (a guard that scanned nothing passed nothing).
"""
import re
import sys

# `$$` glued to a name: "$X.$$", /tmp/x-$$, "$d/$$.tmp", $(mktemp).$$. A lone $$ (echo "$$",
# kill $$) is not a file name.
PID_NAME = re.compile(r"""[\w})\].\-/]\$\$""")
# printf|echo|cat writing a file (> or >>) with the stderr silencer AFTER it, at the start of
# a command: line start, after ; & | (, or after then/do/if/else.
LATE_REDIRECT = re.compile(
    r"""(?:^|[;&|(]|\b(?:then|do|if|else)\b)\s*(?:printf|echo|cat)\b[^#|;&<>]*(?<![2&>])>>?\s*"""
    r"""("[^"]*"|'[^']*'|[^\s"'>|&;]+)\s+2>\s*/dev/null""")


def problems(path):
    out = []
    try:
        lines = open(path, encoding="utf-8").read().split("\n")
    except OSError as e:
        return ["%s: cannot read (%s)" % (path, e.strerror)]
    for n, line in enumerate(lines, 1):
        s = line.strip()
        if not s or s.startswith("#") or "hygiene-ok" in line:
            continue
        if PID_NAME.search(line):
            out.append("%s:%d: temp name built from $$ is predictable in a shared dir; use mktemp (or mkdir for a lock)" % (path, n))
        if LATE_REDIRECT.search(line):
            out.append("%s:%d: '> file 2>/dev/null' leaks the error from opening the file; write '{ cmd > file; } 2>/dev/null'" % (path, n))
    return out


def main(argv):
    if not argv:
        print("usage: check-shell-hygiene.py <file> [<file> ...]", file=sys.stderr)
        return 2
    found = [p for f in argv for p in problems(f)]
    for p in found:
        print(p)
    return 1 if found else 0


if __name__ == "__main__":
    sys.exit(main(sys.argv[1:]))
