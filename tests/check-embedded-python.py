#!/usr/bin/env python3
"""Fail when a `python3 -c '...'` block in a shell script is cut short by a quote.

The scripts now run the interpreter scripts/find-python.sh resolved, as
`"${PY[@]}" -c '...'`; both spellings are scanned.

The shell string ends at the FIRST single quote after the opening one — so an
apostrophe anywhere in the program, including in a comment, silently shortens it.
Bash then parses the remainder as arguments and redirections, which is usually still
valid shell: `bash -n` passes, shellcheck passes, and the truncated program runs and
returns nothing useful. With stderr on /dev/null, as these blocks have, the caller
simply sees "no findings".

Two signals separate a truncation from a real end, and either one is enough:
  * the body ends on a comment line — where an apostrophe in prose lands
  * the body does not compile — where an apostrophe in code lands

A `-c` body must also be ASCII, comments included. The program travels as argv, and
Linux Python under a C locale decodes argv as ASCII with surrogateescape, so one em
dash makes the whole program a SyntaxError that `2>/dev/null` hides. A heredoc is
read as UTF-8 source bytes and is not affected.
"""
import sys

EARLY = " — a quote ended the shell string early"
OPENS = ("python3 -c '", "\"${PY[@]}\" -c '")


def problems(path):
    src = open(path, encoding="utf-8").read()
    out = []
    at = 0
    while True:
        hits = [(i, o) for o in OPENS for i in [src.find(o, at)] if i >= 0]
        if not hits:
            return out
        i, opener = min(hits)
        start = i + len(opener)
        end = src.find("'", start)
        at = end + 1 if end >= 0 else start
        if end < 0:
            out.append((path, src.count("\n", 0, start) + 1, "never closed" + EARLY))
            continue
        body = src[start:end]
        line = src.count("\n", 0, start) + 1
        for k, text in enumerate(body.split("\n")):
            if any(ord(ch) > 127 for ch in text):
                out.append((path, line + k, "holds non-ASCII (a C locale cannot decode argv)"))
        last = body.rstrip("\n").split("\n")[-1].lstrip()
        if last.startswith("#"):
            out.append((path, line + body.count("\n"), "ends inside a comment" + EARLY))
            continue
        try:
            compile(body, path, "exec")
        except SyntaxError as e:
            out.append((path, line, "does not compile (%s)" % e.msg + EARLY))


if __name__ == "__main__":
    found = []
    for p in sys.argv[1:]:
        found += problems(p)
    for path, line, why in found:
        print("%s:%d: embedded python %s" % (path, line, why))
    sys.exit(1 if found else 0)
