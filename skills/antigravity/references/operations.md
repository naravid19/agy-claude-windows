# Operations — write grants, model availability, limits

Moved out of `SKILL.md` so it is read only when a delegation fails or a model question comes up.

## Write grants in full

- **Write tasks need a grant — and it does not have to be `--yolo`.** Headless agy's no-permission behavior has shifted
  every few releases — describe-only (pre-1.1.0), scratch-divert (1.1.0–1.1.2), soft-deny
  with a stderr notice (1.1.3+), **hard error by 1.1.13**, soft again from **1.1.20**
  (measured on 1.1.25; since 1.1.27 also named in the envelope's `denied_actions`, 1.2.0) — but **your workspace stays
  untouched every time**; what varies is whether the run admits it (issue #10). The
  wrapper maps the soft deny and the hard error alike to exit 15. **Two things grant a write, and `--yolo` is
  the blunt one.** A `write_file(<dir>)` entry under `permissions.allow` in
  `~/.gemini/antigravity-cli/settings.json` allows writes **recursively beneath `<dir>`**
  with no flag at all — confirmed on agy 1.1.9 by a controlled A/B (#37): covered target
  wrote, uncovered target returned `PERMISSION_DENIED`, rule the only variable. agy's own
  denial text names the rule and offers `--yolo` as the *alternative*. `--yolo` auto-approves
  **all** tools and is what you need when no rule covers the target, or for web search / URL
  reads (agy 1.1.28 made those ask first; the narrow rule is `read_url(<target>)`) / Vertex AI
  Search / terminal. Not verified below 1.1.9; a glob form (`write_file(/path/**)`) was
  reported not to match. `<dir>` is a placeholder: left as written the rule grants nothing
  on any version — exit 15 with the rule visibly present in the file. Separately, and only
  for `command(...)`, an entry naming no command (`command(time)`, comment-only, `()`)
  matched EVERY command before 1.1.11; do not attach that history to a mistyped
  `write_file()`. If a user reports a rule that "should" work, have them run `agy-doctor`
  before changing anything else.
  Run write tasks on a branch and verify with `git status`.
  **In a `bypassPermissions` session the plugin's `PreToolUse` hook adds `--yolo` to
  delegate and background-job calls for you** (it inherits what the user already granted and
  never escalates a prompting session); pass `--no-yolo` to keep one call unapproved. Claude Code may
  prompt for or block `--dangerously-skip-permissions` — approve it or pre-allow
  `Bash(*agy-delegate*)`. Always verify files actually changed **in the workspace** with
  `git status` (the wrapper maps BOTH denial shapes — the soft deny, 1.1.3+ and again from
  1.1.20, and 1.1.13's hard error — to exit `15`, so you're not left guessing).

## Model availability and pricing notes

> **Model availability moves fast, and `--tier` needs agy ≥ 1.1.10.** Until 1.1.10, agy
> **ignored `--model` and `--effort` in headless `-p`** — the flag was applied after model
> configuration had initialised, so the run silently fell back to the persisted default.
> This wrapper resolves every `--tier` to `--model` and always runs `-p`, so on an older
> agy **tier selection does nothing and looks like it works**: the call succeeds, returns
> sensible text, reports usage. `doctor` warns when it sees one — and on agy ≥ 1.1.11 it
> stops inferring and **asks**: it requests a tier model via `-p /model` (a read-only slash
> command that costs no tokens and starts no agent turn) and reports which model agy says
> it would actually run. Below 1.1.11 it does not probe, because there the slash command
> falls through as prompt text and the model answers as though it had run.
>
> The `flash` tiers default to the **newest Gemini Flash (High)** / **(Low)** that `agy models`
> lists, read from a cache so a delegation never waits for the slow `agy models` (pinned to
> Gemini 3.8 Flash until one is cached; an exact `tier_flash` / `--model` wins). Gemini 3.8 has been
> the default since 0.26.0 (3.7 from 0.24.0, 3.5 before). 3.8, 3.7 and 3.6 carry identical list prices —
> $0.75 in / $3.75 out / $0.075 cached-in per 1M — under a promotion that **ends
> 2026-12-31** and then settles at $1.50 / $7.50 / $0.15; 3.5 is $1.50 / $9.00 /
> $0.15 throughout. Two sources, checked 2026-09-03. Price a run with
> `prices.json`'s `gemini_flash`, which mirrors whatever the flash tier resolves to;
> `agy-cost-compare` picks that key by tier NAME, not by model.
>
> **The move is justified on currency at an unchanged list price, not on quality** —
> no comparison has been run between these models on a build where `--model`
> actually applies, and an identical per-token price is not an identical per-task
> cost (thinking bills as output; read the `AGY_USAGE` line). Measured quirk: under
> `--digest`, a prompt with nothing to inspect (a bare "reply OK") makes 3.8 High run a
> command to find something to report — 6 of 7 runs, exit 15 headless without a grant;
> 3.7 High 0 of 3. With a real task (a file behind `--dir`, pasted code) 3.8 High
> answered 6 of 6. Give it a task, or drop `--digest` for a ping. If a plan does not
> serve 3.8 — agy 1.1.25's note lists it for `GEMINI_API_KEY` sign-in; it is also
> listed on the GCP-project sign-in this was measured on — `doctor` says so and a
> delegation exits 14 naming the fix; remap `tier_flash` to a name from
> `agy models` (3.7 and 3.6 cost the same).
>
> **Retracted:** earlier versions of this note quoted token-level comparisons between
> 3.5 / 3.6 / `flash-medium` (−23% input, `cache_read` +43%, and so on). Those runs were
> made on agy 1.1.8–1.1.9, where `--model` was ignored — so every arm may have executed
> the same persisted default. Independently, the numbers did not survive their own ranges:
> 3.5-high spanned [421k, 509k] input against 3.6-high's [305k, 412k] at n=2, and
> `flash-medium` overlapped `high` outright. A mean-vs-mean claim over overlapping ranges
> is exactly what this repo's own playbook tells you not to report. Pick a tier by what
> your plan serves and by the published rates until this is re-measured on 1.1.10+.
>
> Note: agy 1.1.5 changed `agy models` output to slugs (`gemini-3.5-flash`); both slugs and
> display names are accepted by `--model`, and `doctor` matches either.

## Prerequisites & limits

- `agy` installed and authenticated (`agy models` lists Gemini models); its
  `~/.gemini/antigravity-cli/settings.json` points at a GCP project/region.
- Scripts executable (`chmod +x scripts/*.sh`).
- agy v1.0.x: `-p` takes the prompt as its value (wrapper handles); no JSON output;
  print mode returns final text only (no trajectory); no `timeout(1)` on macOS (use
  `--timeout`).
- **WSL:** `--add-dir` on a Windows mount (`/mnt/c/...`) reads over a slow 9p bridge —
  calls can take 20s+. Keep the repo on the Linux filesystem (`~`); the wrapper warns.

