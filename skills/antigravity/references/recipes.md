# Recipes — concrete `agy-delegate` commands

Moved out of `SKILL.md` so it is read only when a call is not a plain single delegation.

## SDLC recipes

```bash
ROOT="${CLAUDE_PLUGIN_ROOT}/bin/agy-delegate"

# Scaffold from a spec (Claude wrote the spec/architecture)
"$ROOT" --tier pro --yolo --dir ./app \
  "Scaffold per ARCHITECTURE.md: dirs, configs, stub modules. Follow AGENTS.md."

# Generate tests for a contract Claude defined
"$ROOT" --tier flash --yolo --dir ./app \
  "Write unit + edge-case tests for src/payments.py covering the cases in SPEC.md."

# First-pass review (Claude does the final pass)
"$ROOT" --tier pro "Review for bugs/security/perf, be skeptical. List file:line: <diff>"

# Implement-until-tests-pass (feedback loop; isolate on a branch)
"$ROOT" --tier pro --yolo --dir ./app \
  "Implement feature X to satisfy AGENTS.md and make 'pytest -q' pass. Iterate until green."

# Migration / modernization
"$ROOT" --tier pro --yolo --dir ./svc \
  "Migrate all callers from APIv1 to APIv2 per MIGRATION.md. List every file changed."

# Web search → Claude re-checks
"$ROOT" --tier pro --yolo "Use web search for <X>. Give URLs + dates."

# Audio / video / image understanding (Claude can't hear or watch; Gemini can)
# agy-media writes the full transcript to a FILE and returns a timestamped digest —
# never ingest a whole transcript (a 1-hour recording is ~10k words of cache_read).
"${CLAUDE_PLUGIN_ROOT}/bin/agy-media" ./meeting.wav "decisions and owners"     # digest -> you; transcript -> ./meeting.transcript.md
"${CLAUDE_PLUGIN_ROOT}/bin/agy-media" ./demo.mp4 --timeout 20m                 # video: adds timestamped VISUALS/OCR
"${CLAUDE_PLUGIN_ROOT}/bin/agy-media" ./memo.m4a --convert                     # agy mishandles m4a/aiff; converts to wav first
# Verify before relying on it: the digest flags unclear audio + uncertain names/numbers —
# grep that timestamp out of the transcript file rather than trusting the summary.

# Vertex AI Search over internal data (discover engines, then query)
"$ROOT" --tier pro --yolo "List Vertex AI Search engines (list_engines)."
"$ROOT" --tier pro --yolo "Search engine <ENGINE_ID> for: <question>. Cite the hits."
```

## Internal fan-out recipe (agy spawns its own subagents)

agy has built-in `define_subagent` / `invoke_subagent` tools. Which pattern works is
**version-dependent** — this surface is moving fast upstream (4 releases in one week
while we tracked it), so re-verify after any agy upgrade:

- **agy ≥ 1.0.16 — dynamic custom subagents (preferred):** have agy `define_subagent` a
  named specialist in-session (name / description / system_prompt), then
  `invoke_subagent` it by that TypeName. **Verified headless on 1.0.16 and re-verified
  on 1.1.0**: define → invoke → result round-trips cleanly, real thread spawned.
  (1.0.13–1.0.15 shipped this broken — defined agents failed to invoke, upstream #521;
  fixed in 1.0.16. Subagents are officially documented as of 1.1.0 —
  antigravity.google/docs/cli/subagents — with static config at
  `<workspace>/.agents/agents/*.md` and global `~/.gemini/config/agents/`.)
- **Any version — role delegation (fallback):** the sandbox pre-approves TypeNames
  **`self`** and **`research`**; an *undefined* custom TypeName is rejected with
  `CORTEX_STEP_TYPE_INVOKE_SUBAGENT: ... not found or not allowed to be invoked`
  (upstream #105). Invoke TypeName `self` and inject the specialty via `Role` +
  `Prompt` — verified on 1.0.12 **and re-verified on 1.0.16**.

Use it for **orchestrator-mode work pushed down a level**: instead of Claude dispatching
N parallel `agy-job` runs (N round-trips, coordination spend on the frontier side), send
ONE delegation and let agy fan out internally — the coordination tokens land on the
cheap side, and you ingest a single digest.

```bash
# Preferred form (agy >= 1.0.16). --yolo (the wrapper's flag; it reaches agy as
# --dangerously-skip-permissions) is required so the subagent tools aren't
# soft-denied headless (see below). Verified live on agy 1.1.5.
"${CLAUDE_PLUGIN_ROOT}/bin/agy-delegate" --dir . --yolo --digest --timeout 10m \
  "ACTUALLY use your define_subagent and invoke_subagent tools (do NOT simulate).
   Decompose <task> into up to 3 units. For each unit: define_subagent a named specialist
   (name + system_prompt for its role, following this repo's conventions / AGENTS.md if
   present), then invoke_subagent it by TypeName with the unit's work. Wait for ALL, then
   report per-unit results, EACH subagent's conversationId, and end with a DIGEST line."
# Any-version fallback: replace define/invoke with TypeName "self" + a specialist Role.
```

Verified behaviors (1.0.12 → 1.1.5):
- **Pass `--yolo`.** On 1.1.3+ the subagent tools need permission that headless mode
  can't prompt for, so without `--yolo` the spawn is denied (wrapper exit 15). Whether
  it is a soft deny or the hard error 1.1.13 introduced for writes (and 1.1.20 took
  back) has not been measured for this tool — the grant and the exit code are the same either way.
  (On 1.0.x spawning was ungated, but `--yolo` is the durable choice here: a
  `permissions.allow` `write_file(...)` rule covers file writes only, not
  `define_subagent`/`invoke_subagent`, and not web search, URL reads (agy 1.1.28+) or Vertex AI Search.)
- Each spawn's tool result includes a `logAbsoluteUri` → a **readable step-by-step
  `transcript.jsonl`** under `~/.gemini/antigravity-cli/brain/<conversationId>/` —
  *better* trajectory visibility than a plain delegation. Location unchanged across
  1.0.12→1.1.5, for both `define_subagent` and `self` spawns. Have the parent report
  each `conversationId`, then audit with `"${CLAUDE_PLUGIN_ROOT}/bin/agy-trace" <id>` (`"${CLAUDE_PLUGIN_ROOT}/bin/agy-trace" --list` finds
  recent ones). Note: the parent may also create a coordination thread of its own, so
  `--list` can show one more conversation than the units you asked for.
- Spawns are real and observable (new conversation threads appear) — but still run the
  verification gates on the merged result; more autonomy = more surface for error.

Caveats: neither pattern is a documented contract yet — `self`+Role works around the
sandbox allowlist, and even the official docs' static agent-config paths don't match
observed behavior (upstream #527) — so **re-verify after agy upgrades** (1.0.16 changed
this area within a day of our first verification). Bound the fan-out width in the
prompt (agy chooses parallelism otherwise). A wide fan-out takes longer wall-clock —
raise `--timeout`, and in an interactive session prefer a background job (`agy-job`).

## Deep-research recipe (multi-source)

agy has **no built-in "Deep Research" mode** — that product lives in the Gemini app
and the Gemini API's managed Deep Research Agent, **not the CLI** (verified). But agy
*can* do genuine multi-step, cited web research via its agentic loop. So deep research
is a **Claude-orchestrated recipe**, not a single agy call. Pair it with Claude's own
`deep-research` skill as planner/verifier; agy is the cheap, grounded legwork worker.

Caveat that shapes the recipe (verified empirically): in `--print` mode agy uses
search-**summary** tools and does NOT reliably fetch full pages, so its citations are
coarse (often domain-level) and may not actually support the claim. It can also leak
parametric "knowledge" disguised as a sourced fact. **Never ship its citations
unverified.**

1. **Plan (Claude).** Decompose into sub-questions + an explicit list of load-bearing
   claims to verify. Claude owns scope and final synthesis.
2. **Fan-out fetch (agy, cheap, parallel).** One call per sub-question; force compact
   stdout so bulky pages stay in Gemini's context, not Claude's:
   ```bash
   "$ROOT" --tier flash --yolo \
     "Use web search for <sub-question>. Return 5-8 bullet findings, each with the
      exact source URL and publication date. Output ONLY findings+URLs+dates."
   ```
3. **Deepen on key sources (agy).** For each load-bearing claim, name the URL and make
   agy quote the supporting text (turns domain-level citations into verifiable quotes):
   ```bash
   "$ROOT" --tier pro --yolo \
     "Open <URL> and quote the exact sentence(s) supporting: '<claim>'.
      If the page does not support it, reply NOT SUPPORTED."
   ```
4. **Adversarial verify (Claude).** Corroborate each key claim across ≥2 independent
   domains; treat any single/vague/domain-only citation as unverified; sanity-check
   dates; watch for Gemini parametric knowledge masquerading as a sourced fact.
5. **Synthesize (Claude).** Write the final cited report from verified findings only;
   mark anything uncorroborated as "unverified."

Iteration is Claude's job: `--print` does one agentic pass per call (no auto re-query
when evidence is thin), so Claude must re-dispatch follow-up agy calls to close gaps.
Token economics: bulky searched/fetched text is paid in cheap Gemini tokens and
distilled to bullets+URLs before reaching Claude — use `agy-cost-compare` to show it.

## What Antigravity brings that Claude lacks natively

Built-in Google tools (MCP), verified working in headless `--print` mode:
- **Google / web search** — current, grounded info.
- **Vertex AI Search** — search internal/company data stores (`list_engines`,
  `search`, `conversational_search`).
- **Google Cloud Logging**, **Notebooks** (Colab/Jupyter), **Visualization** (charts).

Tool use in headless mode requires `--yolo` (print mode can't show approval prompts);
search/list tools are read-only so this is low-risk.

