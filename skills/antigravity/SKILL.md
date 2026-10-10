---
name: antigravity
description: Run the Antigravity CLI (Gemini) as a collaborating AI inside Claude Code, with intelligent model routing across the software development lifecycle. Claude is the conductor/orchestrator — requirements, architecture, the hard 20%, verification, and review — and routes deterministic, high-volume work (scaffolding, boilerplate, test generation, first-pass review, migrations, web/Vertex AI Search) to Antigravity (Gemini), the cheaper, faster model. Use when the user wants to "use Antigravity / agy", "vibe code / agentic engineering", "accelerate the SDLC", "delegate to Gemini", "scaffold / generate tests / migrate", "first-pass code review", "search web or internal/company data", "deep research / multi-source research report", "second-model cross-check", or "lower token cost on a big job". Claude always verifies Antigravity's output and re-checks itself if unsatisfied.
version: 0.28.0
---

# Antigravity for Claude Code — hybrid SDLC

Run the **Antigravity CLI (`agy`, Gemini)** as a second AI working alongside Claude
Code. The organizing idea is **intelligent model routing across the SDLC**: keep
judgement-heavy work on Claude (the frontier model) and route deterministic,
high-volume work to Antigravity (cheaper, faster Gemini). Two AIs, one workflow.

- **Claude = conductor / orchestrator** — requirements, architecture, the hard 20%
  (edge cases, integration, correctness), specs, tests/evals, final review.
- **Antigravity = delegated agent** — a full terminal agent (file edits, terminal,
  subagents, MCP, web/Vertex AI Search) that executes well-specified work.

This is **agentic engineering, not vibe coding**: the value is the structure around
the model — routing, shared rules, verification gates — not raw generation.
*Generation is solved; verification, judgement, and direction are the craft.*

## Two modes (pick per task)

- **Conductor (sync, inline):** you're shaping something in real time; delegate a
  small, well-scoped chunk to agy mid-flow (e.g. "generate these tests"), use the
  result immediately.
- **Orchestrator (async, multi-unit):** decompose a larger task into units, dispatch
  to agy (often with `--dir`, agentic, in parallel), then review and integrate.
  Best for migrations, bulk implementation against patterns, test suites.

## Division of labor across the SDLC

Route each phase to the right model. This is the core policy.

| SDLC phase | Owner | Why |
|---|---|---|
| Requirements & planning | **Claude** | ambiguity, human-paced judgement |
| Design & architecture | **Claude** | trade-offs; most human-centric |
| Implementation — complex / architecture-bearing (the 20%) | **Claude** | correctness, deep context |
| Implementation — scaffolding / boilerplate / well-specified | **agy** | deterministic, high volume |
| Test & eval generation | **agy** (Claude defines the contract) | cheaper-model territory |
| First-pass code review | **agy** → **Claude** final | AI as first-pass reviewer |
| Cross-model verification (output + trajectory) | **both** | two model families ≠ same failure |
| Maintenance / migration / modernization | **agy** executes, **Claude** directs | tedious, systematic |
| Web / Vertex AI Search | **agy** → **Claude** re-checks | tools Claude lacks natively |
| Audio / video understanding | **agy** transcribes + digests · **Claude** verifies | Gemini is natively multimodal; no local ffmpeg/speech stack |
| Deep research (multi-source) | **agy** fans out search/fetch · **Claude** plans, verifies ≥2 sources, synthesizes | offload bulky pages to cheap Gemini; frontier model judges |

Routing tier within agy: `flash` (default, bulk) · `flash-lo` (cheapest, trivial) ·
`pro` (harder reasoning / reviews / cross-checks).

**agy is multi-model.** Tiers map to Gemini by default, but you can point delegation at any
model `agy models` lists (Claude / GPT on plans that expose them) — via `--model <exact name>`,
or persistently with the `default_model` / `tier_*` plugin options. Keep the executor a
*different, cheaper* model than the Claude conductor: that's what yields the cost saving **and**
the cross-model verification value (Claude executing Claude loses both).

> **`--tier` needs agy ≥ 1.1.10.** Older agy ignored `--model` and `--effort` in headless `-p`, so a
> tier looked selected and did nothing; `doctor` checks for it. The `flash` tiers default to the
> **newest Gemini Flash (High)** / **(Low)** in `agy models`, read from a cache so a delegation never
> waits for it (pinned to Gemini 3.8 Flash until one is cached); an exact `tier_flash` / `--model`
> wins. Model-availability, pricing and retraction notes: `references/operations.md`.

## How to call it

```bash
"${CLAUDE_PLUGIN_ROOT}/bin/agy-delegate" [options] "the task prompt"
```
Options: `--tier flash|flash-lo|pro` · `--dir <path>` (workspace, repeatable) ·
`--timeout 10m` · `--yolo` (auto-approve **ALL** tools — the blunt grant; needed for web search /
URL reads (agy 1.1.28+; or a `read_url(<target>)` rule) / Vertex AI Search / terminal, and for writes not covered by a `permissions.allow` rule. For a
file write the narrower grant is usually a `write_file(<dir>)` entry in
`~/.gemini/antigravity-cli/settings.json`, which needs no flag — see below. Run write tasks
on a branch) · `--mode accept-edits|plan`
(agy execution mode. `--mode accept-edits` is NOT a headless write grant. Measured on agy 1.1.13 — where the flag is actually applied, since 1.1.12 fixed `--mode` being ignored in headless `-p` entirely — the write is denied exactly like one without it. Earlier notes here said "soft-denied on 1.1.3"; on a build where the flag was never applied, that observation could not tell a denial apart from the flag doing nothing. `plan` = strategize only) · `--sandbox` ·
`--digest` (append a digest-only output contract — use it for any
bulk read/analysis; the wrapper also warns on stderr when a reply comes back dump-sized,
because ingesting digests instead of dumps is the single biggest cost lever) ·
`--print-command` (dry run: show the resolved `agy` call, don't run it) · pipe a long
prompt with a trailing `-`.

The wrapper handles agy's quirks (prompt is the value of `-p`; non-TTY stdout drop via
`< /dev/null`). On **agy ≥ 1.1.8** it also runs agy with `--output-format json`
internally: **stdout still gives you the model's text unchanged**, but failures are
classified from the structured `error` instead of scraped prose, and the executor's real
token usage (input / output / thinking / **cache_read**) is reported as an `AGY_USAGE
{...}` line on stderr — so the Gemini side of a delegation can finally be *measured*, not
estimated. The line also carries `model` and `tier` (the tier the model was derived from;
empty for an explicit `--model`) and agy's `duration_seconds` / `num_turns` (1.2.x; 0 on
older agy), so a log prices itself per tier without a join back to the command. Older agy (or no working Python 3) transparently falls back to the plain-text path;
force it with the `structured_output` option.

> **`AGY_USAGE` accounting (verified):** `total = input + output` (`thinking` is inside `output`);
> `cache_read` is a separate counter, not part of `total` and not a subset of `input`. Price the
> Gemini side as three separate terms. **When measuring, set `AGY_USAGE_LOG=/path/to/log`** (or the
> `usage_log` option): a `2>&1 | tail -N` pipe keeps the digest and silently drops the usage line.
> Details and the measured case: `references/cost.md`.

**Two ways to delegate.** Call the wrapper directly (above), or — when you want file
generation to happen entirely on Gemini with **zero Claude tokens spent writing** — hand
the unit to the **`antigravity-delegate` subagent** (its only file-acting tool is the
wrapper; it returns a digest for you to verify). Either way, *you* still own verification.

**Structured failures.** The wrapper exits `10` quota · `11` auth · `12` timeout (incl. an expired `--print-timeout`, which agy 1.1.28+ returns as a **partial** reply with rc 0 — the wrapper prints it and still exits 12) · `13`
agy-missing · `14` model-unavailable (a `--model` / `tier_*` / `default_model` name not in
`agy models` — agy ≥ 1.1.2 hard-fails instead of silently downgrading) · `15`
permission-denied (a tool needed permission headless — BOTH the soft deny, agy 1.1.3+ and
again from 1.1.20, and 1.1.13's hard error — add a `permissions.allow` rule or pass `--yolo`;
since 1.1.27 the wrapper names the refused tool from the envelope's `denied_actions`)
(besides `2` failed / `3` empty). On agy ≥ 1.1.8 these are derived from the structured
`status`/`error` envelope rather than stderr pattern-matching, so the classification is
reliable. It prints a `AGY_SIGNAL {...}` line on stderr;
`"${CLAUDE_PLUGIN_ROOT}/bin/agy-job" status` / `"${CLAUDE_PLUGIN_ROOT}/bin/agy-job" result` surface it, so you can react (e.g. retry quota with `--continue`,
fix the model name, or add `--yolo`) instead of scraping prose.

**If Claude itself is running headless (`claude -p`, one-shot):** run delegations
**synchronously** — let `agy-delegate` BLOCK and return before you continue. Do NOT
background a delegation expecting a later turn / "harness re-invocation": there is none in
`-p` mode, so you'd exit before the work finishes. (Backgrounding is only valid in an
interactive session that will be re-invoked.)

## Shared harness: one AGENTS.md for both AIs

agy **reads `AGENTS.md`** from the workspace (verified). Keep a single shared
`AGENTS.md` at the repo root (stack, conventions, hard rules, workflow) so Claude and
Antigravity operate under the **same rules** — this raises agy's first-pass success
rate and keeps output consistent (lower OpEx).

**Rule: when delegating any repo work, always pass `--dir <repo-root>`** so agy loads
AGENTS.md and the real code, instead of pasting files into the prompt (cheaper, denser
context).

## Verification gates (non-negotiable)

Claude owns correctness. For anything that ships:
1. **Define the contract first** — Claude writes/owns the tests and evals; they tell
   agy what "correct" means more precisely than prose.
2. **Output eval = actually run it, don't stop at reading the code.** Reading the diff
   is necessary but NOT sufficient — a static review that "looks right" is still vibe
   coding. Execute it: run the tests, launch the app, hit the real API/endpoints, and
   check each acceptance criterion against observed behavior. Verify external
   assumptions empirically (e.g. does the API actually accept that input?) rather than
   trusting the spec's claims. If you cannot run it, say so explicitly — do not mark
   the gate passed.
3. **Trajectory check** — did it take a sane path? (Limit: print mode returns only the
   final text. The per-conversation logs under `~/.gemini/antigravity-cli/conversations`
   are **SQLite `.db` files with opaque blob columns, not human-readable** — don't rely
   on reading them. Instead, have agy **summarize its own steps** as part of its output,
   or keep a session with `--continue`/`--conversation` and ask it to recap.
   **But every run leaves a readable trajectory:** `transcript.jsonl` under
   `~/.gemini/antigravity-cli/brain/<conversationId>/` — for plain delegations too, not
   just internal-fan-out subagents. `agy-delegate` prints the `conversationId` in its
   `AGY_USAGE` line, so cost and trajectory join 1:1. Audit with
   **`"${CLAUDE_PLUGIN_ROOT}/bin/agy-trace" --audit <conversationId>`** (or `--audit --last`): step-type counts plus
   every non-zero exit. A delegation can report SUCCESS while commands inside it failed —
   measured: 6 failed commands inside one overall-"SUCCESS" run. `"${CLAUDE_PLUGIN_ROOT}/bin/agy-trace" <id>` prints
   the full steps; `--list` finds recent ones.
   **What is NOT recorded: the command strings.** Not in `transcript.jsonl`, not in
   `transcript_full.jsonl`, not in `~/.gemini/antigravity-cli/log/cli-*.log`. You get
   *that* a command ran, its exit code and its output. To attribute a filesystem change,
   diff the tree — the trajectory cannot tell you.)
4. **Review every shipping line** — be skeptical of clever code; check imports are real
   packages (hallucinated deps), error handling, edge cases, and that the contract
   itself is internally consistent (examples/placeholders match the verified behavior).
5. **Never trust agy's "GREEN" — re-run the gate yourself in a clean state.** Measured:
   agy will, to make a check pass, **modify the environment itself** — e.g. patch the
   installed package in site-packages, or `MagicMock`-stub a missing dependency — and then
   report success. Before believing a passing test/eval: diff any touched tooling against a
   pristine reference, restore it, and re-run the gate under Claude's own control. agy's
   self-reported pass is a claim, not evidence.
If wrong: retry on `--tier pro`, sharpen the spec, or do that piece yourself.

## Safety for write tasks

Read-only work (search, review, analysis) is low-risk. **When agy writes files or runs
commands** (`--yolo` grants write + terminal):
- **Write tasks need a grant, and it does not have to be `--yolo`.** Without one, headless agy
  leaves the workspace untouched and the wrapper exits `15`. Two grants work: a
  `write_file(<dir>)` entry under `permissions.allow` in `~/.gemini/antigravity-cli/settings.json`
  (recursive beneath `<dir>`, no flag, the narrow one; `<dir>` is a placeholder and `agy-doctor`
  checks that agy can parse your entry), or `--yolo`, which approves **all** tools and is what web
  search, URL reads, Vertex AI Search and terminal tools need when no rule covers them.
  **In a `bypassPermissions` session the plugin's `PreToolUse` hook adds `--yolo` to delegate and
  background-job calls for you** (it inherits what the user already granted and never escalates a
  prompting session); pass `--no-yolo` to keep one call unapproved. Claude Code may prompt for or
  block `--dangerously-skip-permissions` — approve it or pre-allow `Bash(*agy-delegate*)`. Always
  verify files actually changed **in the workspace** with `git status`. How the denial behaved on each
  agy version, and the exact rule pitfalls: `references/operations.md`.
- Run it on a **dedicated git branch or worktree** so changes are isolated.
- `--sandbox` is NOT execution containment. Measured on macOS with agy 1.1.19: with `--yolo`, `--sandbox` changed nothing — a write to an absolute path OUTSIDE `--dir` succeeded (rc 0), `id` ran and returned a real uid, and `curl https://example.com` returned 200. agy's own help says "terminal restrictions"; whatever it restricts, it is not those, and not in this combination. Not tested on Linux. Contain by what you check
  out and by `permissions.allow`, not by the flag.
- **Claude reviews the diff before merging** — never auto-merge agy's writes.

## Cost discipline — where the savings actually come from

Delegation does **not** save money by itself. Measured reality: on a small task the
hybrid cost *more* than Claude-only, because the dominant cost was Claude's own
`cache_read` — re-reading a large, growing context across many orchestration turns.
The savings the "Gemini sub-agent" concept promises are real, but only when you keep
Claude's context lean and the round-trips few. Apply these as hard rules:

1. **Delegate above the break-even, not below.** Hand work to agy only when the offloaded
   volume **clearly exceeds** the spec-writing + round-trip + verification overhead it
   adds. Bulk/parallel/repetitive (mass migration, exhaustive tests, fan-out research,
   long-context reads that return a small digest) = delegate. Small, self-contained, or
   judgement-heavy = just do it yourself. (Delegating a tiny task is a *net loss*.)
2. **Keep Claude's context lean (the biggest lever).** Do **not** pull the files agy
   already handled (`--dir`) back into Claude's context, and do **not** paste agy's raw
   bulky output into the thread. Claude ingests a **digest**, not raw content — this is
   what collapses the per-turn `cache_read` that made the hybrid expensive.
3. **Make agy return a digest, not a dump.** End every delegation prompt with an explicit
   trailer instruction, e.g.:
   `"...End with a fenced block ===DIGEST=== listing: files changed, key decisions, and a 1-paragraph 'context for next step'. Put bulky detail ONLY in files, not in your reply."`
   Claude reads the DIGEST; the bulky work stays on cheap Gemini tokens.
4. **Batch, don't chatter.** One large, fully-specified delegation beats many small
   round-trips (each round-trip re-reads context = `cache_read` tax).
5. **Review the diff, not the whole tree.** `git diff` is compact; reading every file is
   not.
6. **Do not hold state on the executor to save money — measured, it costs more.** A
   `--continue` call cost **+82% / +277%** vs a fresh one (n=2). Use `--continue` to resume after
   a quota or timeout failure; get multi-step savings from rule 4 (one large delegation).
7. **Asymmetric effort.** The conductor doesn't need max reasoning effort to coordinate +
   verify; run Claude at a moderate effort and let the cheap workers do the volume.
8. **Don't fight the prompt-cache TTL on small tasks (measured trap).** Do NOT manufacture
   busy turns to keep the cache warm: it backfires, because frontier `output` costs most. The
   only real fix is scale: make each delegation big enough that the displaced Claude output
   dwarfs the one-time re-cache cost. Below the break-even the hybrid loses (`docs/AB-RESULTS.md`).

Honest framing for any cost claim: there is **no flat 8×/46%**. Below the break-even the
hybrid costs more; above it, lean-context routing cuts frontier-model spend by a
*measured* margin. Quote the measured number and the break-even, never a headline ratio.
Use `agy-cost-compare` for the per-token gap (estimate; set real Vertex rates first).

Measured detail on batching, `--continue` and the prompt-cache TTL: `references/cost.md`.

## Recipes

Concrete `agy-delegate` commands (SDLC recipes, internal fan-out, deep research, audio/video and
Vertex AI Search) and what Antigravity brings that Claude lacks natively live in
`references/recipes.md`. Read it before composing a call that is not a plain single delegation.

## Reference files

Read these only when you take that path; the rules above are enough for a plain delegation.

- `references/recipes.md` — concrete commands: SDLC, internal fan-out, deep research, media.
- `references/cost.md` — measurements behind the cost rules, the batching benchmark, `AGY_USAGE` accounting, economics.
- `references/operations.md` — the write-grant history by agy version, model availability and pricing notes, prerequisites and limits.
