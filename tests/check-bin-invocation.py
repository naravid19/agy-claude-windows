#!/usr/bin/env python3
"""Fail when a command, skill or agent markdown file invokes a plugin bin/ tool by bare name.

Claude Code documents plugin bin/ as on the Bash tool's PATH, but on Windows no plugin
bin/ reaches PATH for any plugin. Markdown instructions must invoke tools as
"${CLAUDE_PLUGIN_ROOT}/bin/<tool>" (quoted, because paths can contain spaces).
See ADR-0003.

This check ensures no markdown body instructs Claude to execute a bare bin/ tool.
"""
import glob
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


def mask_qualified(text, tool):
    """Replace fully-qualified plugin bin invocations with a placeholder."""
    # Match both "${CLAUDE_PLUGIN_ROOT}/bin/tool" and ${CLAUDE_PLUGIN_ROOT}/bin/tool
    text = text.replace(f'"${{CLAUDE_PLUGIN_ROOT}}/bin/{tool}"', "__QUALIFIED__")
    text = text.replace(f'${{CLAUDE_PLUGIN_ROOT}}/bin/{tool}', "__QUALIFIED__")
    return text


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

            clean_line = mask_qualified(line, tool)
            if tool not in clean_line:
                continue

            # Case 1: Inside bash/sh/shell/untyped code blocks
            if in_code_block and block_lang in ("bash", "sh", "shell", ""):
                if clean_line.strip().startswith("#"):
                    continue
                cmd_patterns = [
                    r"^\s*" + re.escape(tool) + r"\b",
                    r"=\s*" + re.escape(tool) + r"\b",
                    r"\$\(\s*" + re.escape(tool) + r"\b",
                    r"\|\s*" + re.escape(tool) + r"\b",
                    r";\s*" + re.escape(tool) + r"\b",
                    r"(&&|\|\|)\s*" + re.escape(tool) + r"\b",
                ]
                for cp in cmd_patterns:
                    if re.search(cp, clean_line):
                        out.append((path, line_no, tool, line.strip()))
                        break

            # Case 2: Inline code spans `...`
            code_spans = re.findall(r"`([^`]+)`", line)
            for span in code_spans:
                clean_span = mask_qualified(span, tool)
                if tool not in clean_span:
                    continue
                span_patterns = [
                    r"^\s*" + re.escape(tool) + r"(\s+.*)?$",
                    r"\|\s*" + re.escape(tool) + r"\b",
                    r"\$\(\s*" + re.escape(tool) + r"\b",
                    r";\s*" + re.escape(tool) + r"\b",
                    r"(&&|\|\|)\s*" + re.escape(tool) + r"\b",
                ]
                for sp in span_patterns:
                    if re.search(sp, clean_span.strip()):
                        tokens = clean_span.strip().split()
                        # Standalone tool name mention in backticks without arguments
                        # is prose unless preceded by "Run" (and not "have them run")
                        has_run = re.search(r"\b[Rr]un:?\s*`" + re.escape(tool) + r"`", line)
                        is_have_them = re.search(r"\bhave\s+them\s+run\s*`" + re.escape(tool) + r"`", line, re.IGNORECASE)
                        if len(tokens) == 1 and not (has_run and not is_have_them):
                            continue
                        out.append((path, line_no, tool, span.strip()))
                        break

            # Case 3: Outside backticks: "Run: <tool>"
            run_match = re.search(r"\b[Rr]un:\s+([^\s`]+)", line)
            if run_match and run_match.group(1) == tool:
                out.append((path, line_no, tool, line.strip()))

    return out


def usage():
    print(f"Usage: {sys.argv[0]} <file-or-glob> [<file-or-glob> ...]", file=sys.stderr)
    sys.exit(2)


if __name__ == "__main__":
    if len(sys.argv) < 2 or sys.argv[1] in ("-h", "--help"):
        usage()

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
