<a id="readme-top"></a>

<div align="center">

# 🛰️ Antigravity for Claude Code

**Run the Antigravity CLI (Gemini) as a collaborating sub-agent, right inside Claude Code.**
![Antigravity for Claude Code — Claude directs, Gemini executes](docs/hero.png)
Claude conducts the judgement; Gemini does the heavy lifting — intelligent model routing across the SDLC.

[![CI](https://github.com/naravid19/agy-claude-windows/actions/workflows/ci.yml/badge.svg)](https://github.com/naravid19/agy-claude-windows/actions/workflows/ci.yml)
[![License: MIT](https://img.shields.io/badge/license-MIT-green.svg)](LICENSE)
[![Windows fork](https://img.shields.io/badge/fork-Windows%20(Git%20Bash)-0078D6?logo=windows&logoColor=white)](#-about-this-fork)
![Claude Code plugin](https://img.shields.io/badge/Claude%20Code-plugin-5A4FCF?logo=claudecode&logoColor=#D97757)
[![Antigravity CLI](https://img.shields.io/badge/Antigravity%20CLI-agy-4285F4?logo=googlegemini&logoColor=white)](https://antigravity.google/docs/cli-using)

</div>

---

<details open>
<summary><b>Table of contents</b></summary>

1. [Quick look](#-quick-look)
2. [About this fork](#-about-this-fork)
3. [Why](#-why) · [What it does](#-what-it-does) · [Measured results](#-measured-results)
4. [Install](#-install) · [Windows requirements](#-windows-requirements)
5. [Slash commands](#-slash-commands)
6. [Contributing](#-contributing)
7. [Acknowledgments](#-acknowledgments) · [Contact](#-contact)

</details>

---

## ⚡ Quick look

![Antigravity for Claude Code demo](docs/demo.gif)

Claude stays the conductor; the bulk, token-heavy read ran on cheaper Gemini, and Claude verified the result.

---

## 🪟 About this fork

This repository, [`naravid19/agy-claude-windows`](https://github.com/naravid19/agy-claude-windows), is a personal fork of [`yuting0624/antigravity-for-claude-code`](https://github.com/yuting0624/antigravity-for-claude-code). It forked at upstream `0.28.0` (`97f8d13`) with one goal: make the plugin work on **native Windows under Git Bash**, with no WSL and no ConPTY bridge. Everything else is upstream's, unchanged.

What the fork adds:

- **Windows runs natively.** agy ≥ 1.2.11 under Git for Windows, a `windows-latest` CI job, and LF pinned in `.gitattributes` ([ADR-0001](docs/adr/0001-windows-via-git-bash-no-pty-bridge.md)).
- **Prompts go over stdin** as a `stream-json` event, past Windows' 32,767-character command-line cap ([ADR-0002](docs/adr/0002-prompt-over-stdin-everywhere.md)).
- **Tools are called by `${CLAUDE_PLUGIN_ROOT}/bin/<tool>`**, because Claude Code on Windows does not put plugin `bin/` on `PATH` ([ADR-0003](docs/adr/0003-invoke-bin-by-plugin-root-path.md)).
- **A Python that actually runs** is found (`python3`, `python`, `py -3`), skipping the Microsoft Store alias stub.
- **UTF-8 everywhere**, not the locale code page, so Thai Windows (cp874) behaves.
- **`agy-job cancel` kills the whole native process tree**, and `doctor` checks Git Bash, agy and Python.
- **A tighter delegate gate**: a variable can no longer stand in for the wrapper's path.

The full list, with commits, is under [`[Unreleased]` in the CHANGELOG](CHANGELOG.md). Each change here is tested by `tests/run-tests.sh`, which also runs on Ubuntu and on macOS `/bin/bash` 3.2 in CI.

**Built with:** Bash (3.2-compatible) · Python 3 standard library only · [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) · GitHub Actions on Ubuntu, macOS and Windows.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 💡 Why

| | Claude (conductor) | Gemini / `agy` (executor) |
|---|---|---|
| **Owns** | requirements · architecture · the hard 20% · **verification** · review | scaffold · implementation · test generation · search |
| **Strength** | judgement | cheap, fast throughput |

```
you → Claude Code (conduct: design / verify / review)
         └── agy → Gemini (execute: implement / test / search)
```

> *Generation is solved; verification, judgement, and direction are the craft.*

## ✨ What it does

- **Routes work across the SDLC** — Claude keeps the judgement calls; Antigravity handles scaffolding, **test generation**, **first-pass review**, and **migrations** under a shared `AGENTS.md`.
- **Adds tools Claude lacks natively** — live **Google/web search**, **Vertex AI Search** over your internal data, deep research, Cloud Logging. Claude reviews and re-checks the results.
- **Hears audio, watches video** — `/antigravity:media` delegates the perception to Gemini (natively multimodal, **no local ffmpeg/Whisper stack**): you get a **timestamped digest** while the full transcript is written to a file, so a 1-hour recording never lands in Claude's context.
- **Cross-model verification** — an independent, different-model opinion on your code.
- **Background jobs** — fire a long delegation, keep working, collect later.
- **Internal fan-out** — one delegation, and agy spawns its own subagents on the cheap side (dynamic `define_subagent` on agy ≥ 1.0.16; `TypeName "self"` + Role on any version); each leaves a **readable trajectory** you audit with `agy-trace`.
- **Built-in cost discipline** — measured, not guessed (see below).
- **Drops in with the discipline on** — a `SessionStart` hook injects the *cost-aware*
  routing policy automatically (toggle in plugin settings), and the `antigravity-delegate`
  subagent does file **writing** on Gemini, so Claude spends **no tokens generating file contents**.
- **No slash command required** — the delegate subagent is picked up **proactively** for bulk
  work, and a prompt-level nudge flags bulk-looking requests as delegation candidates.
  Both are advisory: **the break-even judgment stays with Claude** (full auto-routing is a
  measured net loss below the break-even), and the nudge is toggleable (`delegation_nudge`).

## 📊 Measured results

On a **large** ADK multi-agent build (+ `adk eval`), same task / same model, 3 ways:

| | Claude solo @high | solo @max | **hybrid** |
|---|---|---|---|
| frontier cost (COST-WEIGHTED) | 2.62M | 5.34M | **1.91M** |
| quality (`adk eval`) | ✅ 3/3 | ✅ 3/3 | ✅ **3/3** |

→ **−27% vs solo@high, −64% vs solo@max, at equal quality** — and the cheap Gemini work isn't even counted. Savings scale with task size; tiny one-off tasks are cheaper to just run on Claude. Full A/B: [`docs/AB-RESULTS.md`](docs/AB-RESULTS.md).

> **Note on cost figures:** numbers are **estimates** — token counts are approximated and rates live in [`prices.json`](prices.json). **Set your real Vertex rates there before quoting any figure.**

## 🚀 Install

In Claude Code:
```
/plugin marketplace add naravid19/agy-claude-windows
/plugin install antigravity@antigravity-for-claude-code
/antigravity:setup        # verifies agy is installed + authenticated
```

**Prerequisites:** the [Antigravity CLI](https://antigravity.google/docs/cli-using) (`agy`) installed & authenticated (`agy models` lists Gemini models), and Claude Code. For the same-bill cost benefit, run Claude Code on Vertex too.

**Platform support:** macOS, Linux, and **Windows (Git Bash)** are supported targets for headless delegation, as well as WSL. On Windows, agy ≥ 1.2.11 is required (no WSL or ConPTY bridge needed). See [Windows requirements](#-windows-requirements) below.

### 🪟 Windows requirements

On native Windows, the plugin runs directly under **Git Bash** with agy ≥ 1.2.11 (see ADR-0001):

- **Git Bash:** Git for Windows is required. Claude Code executes hooks and the Bash tool through Git Bash.
- **agy ≥ 1.2.11:** Headless delegation without a console requires Antigravity CLI 1.2.11 or later (`agy update`). Older versions could hang without a console.
- **Working Python:** A working Python 3 installation (`python3`, `python`, or `py -3`). If `python3` opens the Microsoft Store, disable its App execution alias in Windows Settings > Apps > Advanced app settings > App execution aliases.
- **Claude Code plugin `bin/` PATH bug:** Claude Code on Windows currently does not place plugin `bin/` directories on the Bash tool's `PATH`. In this fork, all tool references use `"${CLAUDE_PLUGIN_ROOT}/bin/<tool>"` (or slash commands).

## 🧩 Slash commands

<img src="docs/image.png" alt="The /antigravity slash commands in a Claude Code terminal session" width="720">

*The plugin's commands show up natively in Claude Code's `/` menu.*

| command | what it does |
|---|---|
| `/antigravity:setup` | health check — `agy` installed + authenticated, scripts ready |
| `/antigravity:delegate [--tier flash\|pro] <task>` | delegate a subtask to agy under cost discipline, then verify |
| `/antigravity:review [--adversarial]` | independent cross-model review of the current diff; Claude reconciles |
| `/antigravity:research <topic>` | Claude-orchestrated deep research — agy does grounded web legwork, Claude verifies citations across ≥2 sources |
| `/antigravity:media <file> [focus] [--convert]` | understand audio / video / images — agy transcribes + analyzes, returns a **timestamped digest**; full transcript goes to a file, not your context |
| `/antigravity:cloud-run-debug [--service <s>] [--region <r>] [--project <id>] [--since 1h] [--apply]` | diagnose a failing Cloud Run service — agy digests the error logs, Claude infers the root cause + fix; read-only by default (`--apply` writes to a branch) |
| `/antigravity:status [id]` · `:result <id>` · `:cancel <id>` | manage background delegation jobs |
| `/antigravity:migrate [--apply] [--include-repos]` | move an existing Claude Code setup onto agy — skills, CLAUDE.md, memory, MCP, plugins, permissions; dry-run by default, `--uninstall` reverses it |

> Background jobs are for **interactive** sessions (fire-and-collect). In headless `claude -p` (one-shot), delegate **synchronously** — there's no later turn to collect a result.

---

## 📦 Bringing your Claude Code setup across

`/antigravity:migrate` moves an existing Claude Code configuration onto `agy`. Dry-run
by default; `--apply` backs up first and `--uninstall --apply` reverses it. Your
`~/.claude` is never written to.

```
/antigravity:migrate                             # see the plan
/antigravity:migrate --apply                     # global assets
/antigravity:migrate --apply --include-repos     # also AGENTS.md + per-repo memory
```

| your Claude Code asset | becomes |
|---|---|
| `~/.claude/skills/` | read **in place** — a `skills.json` entry, not a copy, so one edit serves both tools |
| installed plugins | `~/.gemini/config/plugins/` via the native importer, with its output repaired |
| `CLAUDE.md` | an `AGENTS.md` symlink beside it |
| auto-memory | always-on rules — global ones in a plugin, per-repo ones in `<repo>/.agents/rules/` |
| MCP servers (project + desktop app) | merged into `~/.gemini/config/mcp_config.json` |
| trusted projects | `trustedWorkspaces` |
| `permissions.allow` | a **proposal file** — see below |
| `~/.claude/agents/` | nothing. A user subagent's `model:` names a Claude tier (`opus` / `sonnet` / `haiku`) and its `tools:` lists Claude tool names, so there is no honest mapping; subagents shipped *inside a plugin* come across with the plugin |
| `~/.claude/CLAUDE.md`, `~/.claude/commands/`, `hooks` in `settings.json` | nothing — only the copies that ship inside a plugin are carried across |
| session history | nothing. Antigravity stores conversations as protobuf blobs inside per-conversation SQLite files; there is no writer |

Two things are deliberately not automatic. **Permissions widen when translated** —
Claude's allow-list holds whole command *lines*, while agy's `command()` matches a
prefix — so the result is written out for review and merged only with
`--apply-permissions`. **`model` / `effortLevel` / `env`** are reported and never
written, because no honest mapping exists.

Worth knowing if you would rather do it by hand: an Antigravity rule without
`trigger: always_on` in its frontmatter is ignored with no error and no warning,
workspace `.agents/` is ignored entirely unless the session is bound to an agy project,
and `agy plugin import claude` finds nothing on a current Claude Code because it only
looks one directory deep. [`docs/MIGRATION.md`](docs/MIGRATION.md) has the full layout
reference, the compatibility matrix, and how each of these was measured.

---

## 🗳️ The same two models, arranged differently

This plugin is one shape of Claude and Gemini working together: **conductor and executor** — judgement on one side, throughput on the other, one workflow. It is also the shape for people who live in a terminal.

[**gemini-studio-mcp**](https://github.com/yuting0624/gemini-studio-mcp) is the same thesis on the other surface: **Claude Desktop**, for the colleagues who will never open one. An MCP server rather than a CLI delegation, and the verb flips from *execute* to *ingest* — Gemini reads the recording, the PDF corpus, the internal search index, and only the digest reaches Claude. The split is not cosmetic: you can hand a developer a `--tier` flag and an `AGENTS.md`, but a business user drags a PDF into a chat window, so the routing that is explicit here is automatic there, and the cost discipline that is a documented practice here is a number printed on every response there. They also fail differently — delegated *writing* can silently not happen and has to be checked against the filesystem; delegated *reading* can quietly summarise away the one paragraph that mattered and has to be checked against citations. Same author as this plugin.

[**quorum-review**](https://github.com/yuting0624/quorum-review) is the third shape: the two as **peers**. Both read the same pull request independently, neither sees the other's output, and where they agree independently *that is the result* — only the disagreements are worth a second opinion. Both run on **one** Google Cloud credential, so no vendor API keys live in the repository. Same author as this plugin.

**This repo is its client zero.** It runs on every pull request opened here, alongside a Claude review — including the ones that change this plugin. Keeping the habit of not quoting numbers we haven't measured, here is what that has actually been worth:

- On a fixture holding three known bugs it found **two, with no false positives**, and reached the correct root cause on one that the single-model review took two rounds to get right.
- Reviewing this repo's own CI, both of its models **independently** caught a fork-guard hole in the review workflow itself — one that would have put an outside contributor's code on the runner next to live credentials.
- It has also produced a confident **false positive that both models agreed on** — the code disproving it lived outside the checkout either model could read.

That last one is the useful lesson, and it cuts against the obvious pitch: two independent scans insure you against *one model's* blind spot. They do not insure you against a gap in what you handed **both** of them.

---

<details>
<summary><b>🛠️ Direct script usage &amp; tiers</b></summary>

```bash
# one-shot delegation (plain text on stdout)
scripts/agy-delegate.sh --tier flash "Summarize this changelog in 3 bullets: ..."

# give Antigravity a workspace for multi-file agentic work
scripts/agy-delegate.sh --tier pro --dir ./src "List every TODO with file:line"

# bulk read -> digest-only reply (the biggest cost lever; wrapper warns on dump-sized replies)
scripts/agy-delegate.sh --digest --dir . "Map the auth flow end to end"

# write task: needs a grant — a permissions.allow write_file(<dir>) rule, or --yolo (run on a branch)
scripts/agy-delegate.sh --yolo --dir ./app "Implement X per SPEC.md"

# live web / Google search — and, since agy 1.1.28, any URL read — need --yolo (or a read_url(<target>) rule) headless
scripts/agy-delegate.sh --tier pro --yolo "Web-search <X>. Give URLs + dates."

# Vertex AI Search over internal data
scripts/agy-delegate.sh --tier pro --yolo "List Vertex AI Search engines (list_engines)."

# cross-model review / stdin / background job
scripts/agy-delegate.sh --tier pro "Review for bugs, be skeptical: <paste>"
cat big-prompt.txt | scripts/agy-delegate.sh -
ID=$(scripts/agy-job.sh start --tier pro --dir . "big task"); scripts/agy-job.sh result "$ID"
```

| tier | model | use for |
|------|-------|---------|
| `flash` (default) | Gemini 3.8 Flash (High) | most bulk work |
| `flash-lo` | Gemini 3.8 Flash (Low) | cheapest, trivial tasks |
| `pro` | Gemini 3.1 Pro (High) | harder reasoning / cross-checks |

**agy is multi-model.** Tiers default to Gemini, but you can use any model `agy models` lists
(Claude / GPT on plans that expose them): pass `--model "<exact name>"`, or set it persistently
via plugin options — `default_model`, or per-tier `tier_flash` / `tier_flash_lo` / `tier_pro`
(env `CLAUDE_PLUGIN_OPTION_*`). Keep the executor a *different, cheaper* model than the Claude
conductor — that's what gives both the cost saving and the cross-model verification.

> **The `flash` tiers moved to Gemini 3.8 Flash in 0.26.0** (3.7 in 0.24.0; 3.5 before that). 3.8, 3.7 and 3.6 carry *identical* list prices — $0.75 in / $3.75 out / $0.075 cached-in per 1M tokens — under promotional pricing that **ends 2026-12-31**, after which all three settle at $1.50 / $7.50 / $0.15 (3.5 is $1.50 / $9.00 / $0.15 throughout). Checked against two sources on 2026-09-03; [`prices.json`](prices.json) carries both sets. No quality claim is made here — the reason to move is currency at an unchanged list price, and this repo has retracted a model comparison before for being measured on a build where `--model` was ignored. An identical *per-token* price is not an identical *per-task* cost: thinking bills as output, nothing here has measured how much of it 3.8 does, so read the `AGY_USAGE` line. One quirk was measured while checking this release: under `--digest`, a prompt that gives agy nothing to inspect (a bare "reply OK" ping) makes 3.8 High run a *command* to find something to report — 6 of 7 runs here, which headless without a grant is exit 15 (3.7 High 0 of 3, 3.8 Medium 1 of 6, 3.8 High without `--digest` 0 of 2). Given a real task — a file behind `--dir`, or code pasted into the prompt — 3.8 High answered 6 of 6. Give it a task, or drop `--digest` for a ping. **If your plan does not serve 3.8 yet** (agy 1.1.25's release note lists it for `GEMINI_API_KEY` sign-in; `agy models` also lists it on the GCP-project sign-in this was measured on, but newer models can lag on enterprise plans) you find out immediately, not silently: `agy-doctor` warns that the tier model is absent from `agy models`, and a delegation exits **14** naming the fix. Remap with the `tier_flash` / `tier_flash_lo` options to anything `agy models` lists — `Gemini 3.7 Flash (High)` and `Gemini 3.6 Flash (High)` cost exactly the same. (agy 1.1.5 switched `agy models` to slugs like `gemini-3.8-flash-high`; both slugs and display names work with `--model`, and `doctor` matches either.)

</details>

<details>
<summary><b>💸 How to actually get the savings (cost discipline)</b></summary>

Delegation doesn't save money by itself — these do (also in the skill):

1. **Delegate above the break-even** — bulk/parallel/repetitive work, not tiny tasks.
2. **Keep Claude's context lean** — don't re-read what agy already handled; take a **digest**, not raw output. (Biggest lever — it collapses `cache_read`.) Enforced in code: `--digest` appends a digest-only output contract, and the wrapper **warns when a reply comes back dump-sized** (tune via the `digest_warn_chars` plugin option).
3. **Batch** — one big delegation beats many round-trips.
4. **Review the diff, not the whole tree.**

`scripts/measure-session.py <session-id>` prints the COST-WEIGHTED + est. USD breakdown for a session (Claude side; Gemini side priced separately). `scripts/agy-cost-compare.sh` shows the per-token gap for a task — **estimates from char-count, so verify `prices.json` first.**

**Running a PoC in your org?** [`docs/POC-PLAYBOOK.md`](docs/POC-PLAYBOOK.md) is the step-by-step method — quality gate first, baseline, one lever at a time, break-even reporting, and org-level rollout/enforcement (incl. Windows/WSL requirements).

</details>

<details>
<summary><b>🚧 Guardrails &amp; known limits</b></summary>

> **Something broken?** See **[docs/TROUBLESHOOTING.md](docs/TROUBLESHOOTING.md)** — symptom-first fixes for Windows/WSL, writes that silently don't happen, quota/auth/timeout codes, and updating.

**Guardrails**
- Always **verify** agy's output (it can be wrong, and may even alter its environment to make a check pass — re-run gates yourself in a clean state).
- `--yolo` auto-approves every tool call — a grant over your whole machine, not over `--dir`.
  **`--sandbox` does not contain it.** Measured on macOS with agy 1.1.19: with `--yolo`, `--sandbox` changed nothing — a write to an absolute path OUTSIDE `--dir` succeeded (rc 0), `id` ran and returned a real uid, and `curl https://example.com` returned 200. agy's own help says "terminal restrictions"; whatever it restricts, it is not those, and not in this combination. Not tested on Linux. Use a throwaway checkout, or a
  `permissions.allow` rule instead of the flag.
- Write tasks: run on a dedicated branch/worktree, review the diff before merging.

**Known limits (agy v1.0.x)**
- `-p`/`--print` **takes the prompt as its value** and must come last — the wrapper handles this.
- `--print` drops stdout on a non-TTY unless stdin is detached (handled via `< /dev/null`). **Structured output arrived in agy 1.1.8** (`--output-format json`): the wrapper now uses it internally on ≥1.1.8 to classify failures from the structured error and to report the executor's real token usage (incl. `cache_read`) as an `AGY_USAGE` line on stderr — stdout is unchanged. Since 0.28.0 that line also names the **model** that ran and the **tier** it was picked from (empty for an explicit `--model`), plus agy's own `duration_seconds` / `num_turns` (1.2.x; 0 on older agy), so a usage log prices itself per tier. Older agy falls back to plain text (toggle with the `structured_output` option). **If you're measuring, set `AGY_USAGE_LOG=/path`** (or the `usage_log` option): stderr is easily lost — `2>&1 | tail -N`, the natural way to keep Claude's context lean, keeps the digest and drops the usage line.
- **Pipe hang and empty-output semantics moved upstream.** agy 1.1.24 fixed the cause of the issue-#37 hang (its MCP children kept the caller's pipes open); the wrapper keeps routing agy's output through files, which costs nothing and still covers older builds. Since agy 1.1.18 a dropped agent stream exits non-zero instead of rc 0 + empty, so the wrapper's exit `3` now means agy genuinely returned nothing (from agy's changelog; not reproduced here).
- **An expired `--print-timeout` is no longer a failure on agy's side (1.1.28).** agy returns the partial reply with rc 0 and one stderr line (`[agy] print timeout after 5s with turn in progress; returning partial output`, measured on 1.2.0) and reports no usage for the turn. The wrapper prints that partial reply and still exits `12`, so a truncated answer never passes as a finished one; `--continue` resumes the conversation.
- **The executor's trajectory is auditable.** Every agy run writes a step-by-step `transcript.jsonl`, and the `conversationId` in `AGY_USAGE` joins it to the cost 1:1. `agy-trace --audit <id>` (or `--audit --last`) shows step-type counts and every non-zero exit — a delegation can report SUCCESS while commands inside it failed. The command **strings** are recorded nowhere, so to attribute a filesystem change you must diff the tree.
- **Two write grants, and the narrow one is not `--yolo`.** Headless agy's
  no-permission behavior has shifted every few releases (describe-only pre-1.1.0 ·
  scratch-divert 1.1.0–1.1.2 · soft-deny 1.1.3+ · **hard error by 1.1.13** · soft again
  from **1.1.20**, measured on 1.1.25: rc 0, empty output, the `auto-denied` notice on
  stderr). An ungranted write always **leaves your workspace untouched**; what changed is
  how the run admits it — a stderr notice from 1.1.3, a failed run on 1.1.13–1.1.19, the
  notice again since 1.1.20
  ([#10](https://github.com/yuting0624/antigravity-for-claude-code/issues/10)). Two things
  grant it:
  
  - **`permissions.allow` in `~/.gemini/antigravity-cli/settings.json`** — a
    `write_file(<dir>)` entry allows writes **recursively beneath `<dir>`** and needs no
    flag. This is the narrower grant and usually the right one.
    **`<dir>` is a placeholder — substitute a real path.** Left as written it grants
    nothing on any agy version, and the write is denied with the rule sitting visibly
    in the file. A *different* mistake is the version-sensitive one: a `command(...)` rule
    that names no command (`command(time)`, a comment-only entry, `()`) matched **every**
    command before agy 1.1.11 and silently auto-approved anything the agent ran — broader
    than the `--yolo` it was chosen instead of. 1.1.11 makes that entry match nothing too.
    `agy-doctor` checks your entries and reports the consequence that actually applies.
  - **`--yolo`** — the wrapper's flag, sent to agy as `--dangerously-skip-permissions` (agy
    1.1.25 rejects a literal `--yolo`) — auto-approves **all** tools, not just
    writes. Needed when no rule covers the target, and for web search / URL reads (agy 1.1.28
    made fetching URLs ask first; the narrow rule is `read_url(<target>)`) / Vertex AI Search /
    terminal tools. Since agy 1.1.27 the wrapper names the refused tool from the envelope's
    `denied_actions` (measured on 1.2.0).
    When Claude Code itself runs in `bypassPermissions` mode, a `PreToolUse` hook adds `--yolo`
    to `agy-delegate` / `agy-job start` for you, since you already allowed unattended tool use
    and headless agy would otherwise no-op the write. It never escalates a session that still
    prompts. Opt one call out with `--no-yolo` (wins over `--yolo`), or turn the hook off with
    the `auto_yolo` option.
  
  Confirmed on **agy 1.1.9** by a controlled A/B ([#37](https://github.com/yuting0624/antigravity-for-claude-code/issues/37)):
  a covered target wrote with no flag; an uncovered one came back `PERMISSION_DENIED` with
  the rule as the only variable. agy's own denial text names the rule and offers `--yolo` as
  the alternative. Not verified on other versions, and a glob form (`write_file(/path/**)`)
  was reported *not* to match. Either way: run write tasks on a branch and verify with
  `git status`; the wrapper maps both denial shapes — the soft one (agy 1.1.3+, and again
  from 1.1.20; re-measured on 1.1.25) and 1.1.13's hard error — to exit `15`.
- **Windows (Git Bash):** headless `agy -p` runs natively without a console on agy ≥ 1.2.11. On older agy builds (< 1.2.11) it could hang with a 0-byte log; `doctor` warns and suggests `agy update`. The wrapper protects with a wall-clock `timeout` guard.
- **WSL:** running agy with `--add-dir` on a Windows mount (`/mnt/c/...`) is very slow — agy reads the workspace over a 9p bridge, so even trivial calls can take 20s+. Keep the repo on the WSL Linux filesystem (`~`). The wrapper and `doctor` warn about this.

</details>

<details>
<summary><b>📦 What's inside · local dev · tests</b></summary>

```
.claude-plugin/   plugin (+ userConfig: default_tier, timeout, coding_policy) + marketplace manifests
skills/antigravity/SKILL.md   WHEN + HOW Claude collaborates with agy
agents/           antigravity-delegate subagent (file work runs on Gemini, not Claude)
commands/         slash commands (delegate, review, research, media, cloud-run-debug, setup, status, result, cancel)
hooks/            SessionStart: agy health check + auto-inject the cost-aware policy
bin/              entrypoints (called as `${CLAUDE_PLUGIN_ROOT}/bin/<tool>`): agy-delegate · agy-job · agy-cost-compare · agy-doctor · cloud-debug · agy-trace · agy-media · measure-session · agy-migrate
scripts/          agy-delegate · agy-job · agy-cost-compare · cloud-debug · agy-trace · agy-media · measure-session · doctor · agy-migrate
docs/             AB-RESULTS (measured A/B) · POC-PLAYBOOK · TROUBLESHOOTING · DEMO-KIT
prices.json       Vertex rate config (verify before quoting)
```

**Local development** (hack on the plugin — loads live files, `$CLAUDE_PLUGIN_ROOT` resolves):
```bash
git clone https://github.com/naravid19/agy-claude-windows ~/agy-claude-windows
claude --plugin-dir ~/agy-claude-windows
```

**Tests** (no dependencies; stubs `agy`):
```bash
bash tests/run-tests.sh
```

</details>

---

## 🤝 Contributing

Early-stage and MIT. The fork's scope is Windows support; general features and fixes belong [upstream](https://github.com/yuting0624/antigravity-for-claude-code) (its [`good first issue`](https://github.com/yuting0624/antigravity-for-claude-code/issues?q=is%3Aissue+is%3Aopen+label%3A%22good+first+issue%22) list is there). Before changing code here, read [CONTRIBUTING.md](CONTRIBUTING.md): run `bash tests/run-tests.sh` and `shellcheck scripts/*.sh tests/*.sh`, and add a line to the CHANGELOG's `[Unreleased]` section.

**Automated review:** PRs get two reviews in CI on top of the usual tests/shellcheck — a Claude review carrying this repo's own contracts, and [quorum-review](https://github.com/yuting0624/quorum-review) — see the section above.

**From a fork:** quorum doesn't run at all. The Claude review runs only once a maintainer **with write access** applies the `claude-review` label — the label alone isn't authorisation, since triage collaborators can apply labels too — and it re-runs on every later push, so an approved review can't go stale behind new commits. Your code never reaches the runner at all — the reviewer sees it as a diff (`gh pr diff`), with this repository's base checkout for context. Nothing of yours is fetched or executed.

---

## 🙏 Acknowledgments

- [Yuting Lin (`yuting0624`)](https://github.com/yuting0624) and the contributors to [`antigravity-for-claude-code`](https://github.com/yuting0624/antigravity-for-claude-code), who wrote the plugin this fork is built on. The MIT [LICENSE](LICENSE) is theirs and is unchanged.
- The [Antigravity CLI docs](https://antigravity.google/docs/home/) and the [Claude Code docs](https://code.claude.com/docs/en/overview), the reference for the fork's design decisions.
- [Best-README-Template](https://github.com/othneildrew/Best-README-Template) for the layout of the fork sections of this README, and [Keep a Changelog](https://keepachangelog.com/en/1.1.0/) for the CHANGELOG format.

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## 📬 Contact

**naravid19** — [github.com/naravid19](https://github.com/naravid19) · Project: [github.com/naravid19/agy-claude-windows](https://github.com/naravid19/agy-claude-windows)

<p align="right">(<a href="#readme-top">back to top</a>)</p>

---

## ⚠️ Disclaimer

Community project. **Not affiliated with, endorsed by, or supported by Google or Anthropic.** "Antigravity", "Gemini", "Claude", and "Claude Code" are trademarks of their respective owners. This plugin orchestrates the third-party `agy` CLI; you are responsible for your own API/cloud costs, credentials, and data-sharing choices. MIT licensed — see [LICENSE](LICENSE).
