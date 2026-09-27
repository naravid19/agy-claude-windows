#!/usr/bin/env python3
"""Fail when a Python open() in a file does not name its encoding.

Without encoding= open() uses the locale code page: cp874 on Thai Windows, cp1252 on a
GitHub Windows runner, ASCII under LC_ALL=C. The repo's files are UTF-8, so a bare
open() works on the author's machine and breaks, or silently garbles, on someone else's.

The scan is textual, so it covers Python embedded in shell scripts (`-c '...'`, `-c
"..."`, heredocs) the same as .py files. A call passes when its arguments contain
`encoding=` or a binary mode ("rb", "wb", ...). `x.open(` is some other API and is
skipped, as is an empty `open()`, which is prose, not a call.
"""
import os
import re
import sys

CALL = re.compile(r"(?<![\w.\-])open\(")
BINARY = re.compile(r"""["'][rwax+]*b[rwax+]*["']""")


def args_of(src, start):
    # ponytail: counts parens without reading strings; a ")" inside a string literal
    # in the arguments would end the call early. None of the repo's calls have one.
    depth = 1
    for i in range(start, len(src)):
        if src[i] == "(":
            depth += 1
        elif src[i] == ")":
            depth -= 1
            if not depth:
                return src[start:i]
    return src[start:]


def problems(path):
    with open(path, encoding="utf-8") as f:
        src = f.read()
    out = []
    for m in CALL.finditer(src):
        args = args_of(src, m.end())
        if not args.strip() or "encoding=" in args or BINARY.search(args):
            continue
        out.append((path, src.count("\n", 0, m.start()) + 1))
    return out


if __name__ == "__main__":
    found, seen = [], 0
    for p in sys.argv[1:]:
        if os.path.isdir(p):      # scripts/* also matches __pycache__
            continue
        found += problems(p)      # a missing path raises: loud, not a vacuous pass
        seen += 1
    if not seen:
        sys.exit("check-open-encoding: no files to scan - a guard that scanned nothing passed nothing")
    for path, line in found:
        print("%s:%d: open() without encoding= - reads with the locale code page" % (path, line))
    sys.exit(1 if found else 0)
