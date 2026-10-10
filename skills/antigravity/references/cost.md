# Cost — measurements behind the rules

The cost *rules* stay in `SKILL.md`. This is the measured detail behind them.

## Batching: the number of delegations is the lever

Rule 4 in `SKILL.md` ("batch, don't chatter") is the one that actually moves the needle, and
here is why, from a benchmark of this plugin
(Opus 5 conductor · Gemini 3.6 Flash High executor · agy 1.1.8 · n=3/arm, cold cache):

**Per delegation the economics are fine. Repeated ingestion is what breaks them.**
Offloading a large corpus works exactly as designed — the conductor's `cache_read` fell
**61%**, it never opened the corpus itself, and each digest came back at ~4k tokens. But
**each `agy-delegate` call is an independent session that shares no cache with the last
one**, so a conductor that delegated 7.3 times against the same corpus paid to ingest it
7.3 times. **Two-thirds of the executor's cost was re-reading material it had already
read.** Break-even on that task was ~5.7 delegations; the one trial that stayed at 5 came
in cheaper than solo Claude, the ones at 9 did not.

So when several delegations work over the same material:

- **Fold related units into ONE fully-specified delegation.** This is the only lever that
  actually removes a re-ingestion. Two questions about one corpus = one delegation asking
  for both, not two delegations.
  **Only fold units that genuinely belong together.** If combining them muddies the spec,
  don't — a vague mega-prompt returns worse work, and re-running it costs far more than
  the re-ingestion you saved. Quality of the spec beats the token arithmetic every time.
- Scope `--dir` to the smallest subtree that contains the work, and expect the executor's
  **read** cost — not its writing — to dominate.
- **Do NOT reach for `--continue` to avoid re-ingestion — measured, it makes things
  worse.** Resuming a session carries the whole prior conversation forward *and* agy
  re-reads the material anyway, so you pay both: on a repeated-corpus digest the continued
  second call cost **+82% and +277%** vs a fresh one (n=2), with `cache_read` 3–14× higher.
  `--continue` is for *resuming after a failure* (quota, timeout) — not a cost lever.

Two supporting facts, both measured: **delegation moves work rather than removing it**
(the hybrid ran ~2.8× the normalized token volume for the same result — it stays
affordable because the executor is cheaper per token, not because it does less), and
**agy's own prompt cache covers only ~2/3 of its context re-reads**, so the executor is
worse than Claude at carrying context. Both push the same way: fewer, larger, session-
reusing delegations.

These are single-configuration measurements from 2026-07 on two task families, not
constants. Treat them as direction, and re-measure on your own workload before quoting
any figure.


## `AGY_USAGE` accounting semantics

> **Accounting semantics for `AGY_USAGE` (verified — get this wrong and your cost math
> is wrong).** `total = input + output` (and `thinking` is *inside* `output`).
> **`cache_read` is a separate counter: it is NOT part of `total`, and it is not a subset
> of `input`** — in an agentic delegation it routinely *exceeds* `input` (measured:
> `cache_read` 1,356,694 vs `input` 243,117 in one delegation). So price the Gemini side
> as `input×in_rate + output×out_rate + cache_read×cached_rate`, three separate terms.
> This differs from the Claude/Harbor side, where cache-read tokens *are* an inner subset
> of the reported input total — don't carry one convention over to the other.
>
> **If you are measuring, set `AGY_USAGE_LOG=/path/to/log`** (or the `usage_log` option).
> `AGY_USAGE` and `AGY_SIGNAL` go to stderr, and the advice two paragraphs down — keep
> Claude's context lean — makes `"${CLAUDE_PLUGIN_ROOT}/bin/agy-delegate" ... 2>&1 | tail -N` the natural thing to
> write. stdout (the digest) is emitted *after* the usage line, so `tail` keeps the digest
> and silently drops the usage. Measured in the wild: a benchmark harness lost most of its
> Gemini-side data exactly this way, which made the hybrid look cheaper than it was. A
> named file cannot be truncated by a pipe.

## Rule 6 in full: do not hold state on the executor

6. **Do not hold state on the executor to save money — measured, it costs more.** It is
   tempting to keep one agy session alive with `--continue` / `--conversation <id>` so the
   working context "lives on the cheap side". It does not work: resuming carries the whole
   prior conversation forward *and* agy re-reads the material anyway, and agy's prompt
   cache covers only ~2/3 of its context re-reads. Measured on a repeated-corpus digest,
   the continued call cost **+82% / +277%** vs a fresh one (n=2). Use `--continue` for what
   it is good at — **resuming after a quota or timeout failure** — and get multi-step
   savings from rule 4 instead (one large delegation, not many small ones).

## Rule 8 in full: do not fight the prompt-cache TTL

8. **Don't fight the prompt-cache TTL on small tasks (measured trap).** The 5-min cache
   expires while you wait on a long agy delegation, so the next turn pays `cache_create`
   (1.25× input) instead of `cache_read` (0.1×). It's tempting to "keep the cache warm"
   with busy turns — **measured: that backfires**, because every warming turn generates
   frontier `output` (5× input), the most expensive class, and net cost goes *up*. Do NOT
   manufacture work to stay warm. Backgrounding a long delegation (Bash `run_in_background`)
   is fine to avoid *blocking*, but it does not make a small task cheaper. The only real
   fix is **scale**: make each delegation big enough that the displaced Claude output
   dwarfs the one-time re-cache cost. Below the break-even, the hybrid loses on cost — three
   optimization variants were tested on a small task and none beat solo Claude (see
   `docs/AB-RESULTS.md`). Delegate for cost reasons only at scale.

## Economics (a financial lever, not the headline)

Routing deterministic, high-volume work to Gemini Flash (≪ Claude per token) is
**intelligent model routing**: higher CapEx (this harness) for lower OpEx (cheap model
does the bulk). Use the cost demo as observability:
```bash
"${CLAUDE_PLUGIN_ROOT}/bin/agy-cost-compare" --tier flash "the task prompt"
```
Estimates only (chars/4; agy exposes no token API in print mode). Set real Vertex rates
via `CLAUDE_IN_PER_M`, `CLAUDE_OUT_PER_M`, `GEMINI_IN_PER_M`, `GEMINI_OUT_PER_M`.

