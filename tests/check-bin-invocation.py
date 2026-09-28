#!/usr/bin/env python3
"""Fail when a command, skill or agent markdown file invokes a plugin bin/ tool by bare name.

Claude Code documents plugin bin/ as on the Bash tool's PATH, but on Windows no plugin
bin/ reaches PATH for any plugin. Markdown instructions must invoke tools as
"${CLAUDE_PLUGIN_ROOT}/bin/<tool>" (quoted, because paths can contain spaces).
See ADR-0003.

This check ensures no markdown body instructs Claude to execute a bare bin/ tool.
"""
import os
import re
import sys

HERE = os.path.dirname(os.path.abspath(__file__))
BIN_DIR = os.path.normpath(os.path.join(HERE, "..", "bin"))
if os.path.isdir(BIN_DIR):
    BIN_TOOLS = {f for f in os.listdir(BIN_DIR) if not f.startswith(".")}
else:
    BIN_TOOLS = {
        "agy-cost-compare", "agy-delegate", "agy-doctor", "agy-job",
        "agy-media", "agy-migrate", "agy-trace", "cloud-debug", "measure-session"
    }


def problems(path):
    try:
        content = open(path, encoding="utf-8").read()
    except OSError:
        return []

    lines = content.split("\n")
    out = []
    in_code_block = False
    block_lang = ""

    for line_no, line in enumerate(lines, 1):
        stripped = line.strip()
        if stripped.startswith("```"):
            if in_code_block:
                in_code_block = False
                block_lang = ""
            else:
                in_code_block = True
                block_lang = stripped[3:].strip()
            continue

        for tool in BIN_TOOLS:
            if tool not in line:
                continue

            # If the tool call on this line is already qualified with ${CLAUDE_PLUGIN_ROOT}/bin/, skip
            if f"${{CLAUDE_PLUGIN_ROOT}}/bin/{tool}" in line:
                continue

            # Case 1: Inside bash/sh/shell/untyped code blocks
            if in_code_block and block_lang in ("bash", "sh", "shell", ""):
                if stripped.startswith("#"):
                    continue
                cmd_patterns = [
                    r"^\s*" + re.escape(tool) + r"\b",
                    r"=\s*" + re.escape(tool) + r"\b",
                    r"\$\(\s*" + re.escape(tool) + r"\b",
                    r"\|\s*" + re.escape(tool) + r"\b",
                ]
                for cp in cmd_patterns:
                    if re.search(cp, line):
                        out.append((path, line_no, tool, line.strip()))
                        break

            # Case 2: Inline code spans `...`
            code_spans = re.findall(r"`([^`]+)`", line)
            for span in code_spans:
                if tool not in span:
                    continue
                if f"${{CLAUDE_PLUGIN_ROOT}}/bin/{tool}" in span:
                    continue
                span_patterns = [
                    r"^\s*" + re.escape(tool) + r"(\s+.*)?$",
                    r"\|\s*" + re.escape(tool) + r"\b",
                    r"\$\(\s*" + re.escape(tool) + r"\b",
                ]
                for sp in span_patterns:
                    if re.search(sp, span.strip()):
                        tokens = span.strip().split()
                        # Standalone tool name mention in backticks without arguments
                        # is prose unless explicitly preceded by "Run:" / "run"
                        if len(tokens) == 1 and not (
                            re.search(r"\b[Rr]un:\s*`" + re.escape(tool) + r"`", line)
                            or re.search(r"\b[Rr]un\s*`" + re.escape(tool) + r"`", line)
                        ):
                            continue
                        out.append((path, line_no, tool, span.strip()))
                        break

            # Case 3: Outside backticks: "Run: <tool>"
            run_match = re.search(r"\b[Rr]un:\s+([^\s`]+)", line)
            if run_match and run_match.group(1) == tool:
                out.append((path, line_no, tool, line.strip()))

    return out


if __name__ == "__main__":
    import glob
    files = []
    for arg in sys.argv[1:]:
        if any(c in arg for c in "*?[]"):
            files.extend(glob.glob(arg))
        else:
            files.append(arg)
    found = []
    for p in files:
        found.extend(problems(p))
    for path, line_no, tool, text in found:
        print(f"{path}:{line_no}: invokes {tool} by bare name — use \"${{CLAUDE_PLUGIN_ROOT}}/bin/{tool}\": {text}")
    sys.exit(1 if found else 0)
