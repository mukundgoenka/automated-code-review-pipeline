Project made for assessment for BusinessLabs.org
My id is 2026-2415
# CI Code-Review Pipeline (Claude Code, non-interactive)

An automated pull-request reviewer that runs **Claude Code in a CI pipeline** and
posts **precise, structured** review comments: real bugs flagged, cosmetic nits
skipped, and consistent depth even on large change-sets.

It is built around five ideas, each fixing a specific failure of the naive
"review this" prompt:

| Problem with naive review                         | Fix in this pipeline                                  |
|---------------------------------------------------|-------------------------------------------------------|
| Hangs in CI waiting for input                     | `claude -p` (print mode) — does the job and exits     |
| Flags trivial style nits, misses real bugs        | Staged prompt: explicit criteria + few-shot examples  |
| Contradicts itself / loses depth on big PRs       | Split into a per-file pass and a cross-file pass       |
| Self-review is biased toward approving            | Each pass is a fresh, independent `claude` instance    |
| Reviews ignore team standards                     | Criteria live in [`CLAUDE.md`](CLAUDE.md), auto-loaded  |
| Output is prose, can't be posted automatically    | Strict JSON findings: file, line, severity, fix        |

---

## Quickstart

```powershell
# Mock mode — no API calls, proves the whole pipeline end-to-end in ~1s
npm run review:mock

# Per-file vs cross-file comparison (shows what each pass uniquely catches)
npm run review:compare

# The real thing — spins up fresh `claude -p` reviewers on the PR diff
npm run review
# or:  powershell -File pipeline/review-pipeline.ps1 -BaseRef main -HeadRef HEAD
```

On Linux/CI use the bash twin (needs `git`, `jq`, `claude`):

```bash
FAIL_ON=high ./pipeline/review-pipeline.sh
```

The pipeline writes [`findings/findings.json`](findings/) (machine-postable) and
`findings/report.md` (human-readable), and **exits non-zero** when anything at or
above `-FailOn` severity is found, so CI can block the merge.

> This repo ships a deliberately buggy sample PR on the `feature/loyalty-checkout`
> branch (15 changed files) so every run has something real to review.

---

## The six steps, and why each matters

### 1. Run Claude Code non-interactively — `claude -p`
A pipeline has no human to answer prompts. Plain `claude "review this"` opens an
interactive session and **waits forever** in CI. `claude -p "review this"` prints
the result and exits. Every model call in this pipeline uses `-p`; the bash version
also wraps each call in `timeout` as a backstop. **Result: the pipeline never hangs.**

### 2. Refine the review prompt in stages
Precision is built incrementally — see [`prompt-evolution/`](prompt-evolution/):

- [`v1-broad.md`](prompt-evolution/v1-broad.md) — "what's wrong with this?" → 6
  cosmetic comments, 0 real bugs. Pure noise.
- [`v2-criteria.md`](prompt-evolution/v2-criteria.md) — adds explicit criteria +
  severity + "stay silent if nothing's real" → false positives disappear.
- [`v3-fewshot.md`](prompt-evolution/v3-fewshot.md) — adds few-shot examples (one
  file that should yield a finding, one that should yield `[]`) and a strict JSON
  contract → the fuzzy "real vs cosmetic" boundary gets calibrated, and output
  becomes machine-postable.

The production prompts are [`pipeline/prompts/per-file.md`](pipeline/prompts/per-file.md)
and [`cross-file.md`](pipeline/prompts/cross-file.md).

### 3. Split large reviews into passes
Asking one prompt to review 15 files at once dilutes attention: it goes deep on the
first few and skims the rest. Instead:

- **Pass 1 — per-file:** one independent `claude -p` run per file. Consistent depth
  because each run sees exactly one file. Catches *local* defects (injection,
  swallowed errors, bad math).
- **Pass 2 — cross-file:** one run over the whole change-set. Catches defects that
  are *invisible* in any single file — a changed function signature whose callers
  weren't updated, a renamed config key still read by its old name.

### 4. Use an independent review instance
`claude -p` starts a fresh process with **no memory of writing the code**. Self-review
rationalizes ("I meant to do that"); a cold reviewer doesn't. Each per-file run is
also independent of the others, so one file's findings can't bias the next.

### 5. Put project context in `CLAUDE.md`
[`CLAUDE.md`](CLAUDE.md) holds the team's review philosophy, the DO-flag / DON'T-flag
lists, the severity rubric, and testing standards. Claude Code auto-loads it on every
run inside the repo, so **changing the rules there changes every review** — no need to
touch the pipeline.

### 6. Output structured findings
Every finding is `{ file, line, severity, issue, suggested_fix }`. That is exactly
what you need to post an inline PR comment, and what the GitHub Actions workflow in
[`.github/workflows/code-review.yml`](.github/workflows/code-review.yml) turns into a
sticky review comment.

---

## The three example prompts (run these in the walkthrough)

### Prompt 1 — real bugs only, ignore style
```powershell
Get-Content src\auth.js | claude -p "Review this file for real bugs only; ignore cosmetic style."
```
`src/auth.js` contains a real **auth bypass** plus cosmetic nits (quote style,
spacing). Real output from this exact command:

```
1. Critical — Auth bypass when token is absent
   `if (!token) return true;` — a missing/empty token returns `true`, so every
   request with no Authorization header is treated as authenticated.
   Fix: `if (!token) return false;`
2. High — Tokens generated with Math.random() (not a CSPRNG); use crypto.randomBytes.
3. Medium — Expired sessions never evicted from activeSessions (memory leak).
```
Note what it did **not** say: nothing about quotes, semicolons, or naming. Criteria
beat noise.

### Prompt 2 — per-file pass, then cross-file pass, and compare
```powershell
powershell -File pipeline/review-pipeline.ps1 -Mock -ComparePasses
```
The per-file pass finds local bugs in each file. The cross-file pass finds what the
per-file pass **structurally could not** — because each per-file run only saw one
file:

```
Per-file pass : 15 local issue(s) across 12 file(s)
Cross-file pass: 4 contract issue(s) the per-file pass could not see:
   - src/orders.js:15 [high]  formatPrice() now needs a `currency` arg; this caller passes one arg
   - src/api.js:16   [high]   same formatPrice contract break in quote()
   - src/db.js:21    [medium] reads config.DB_TIMEOUT, but config.js now exports DATABASE_TIMEOUT
   - src/api.js:20   [medium] same DB_TIMEOUT rename mismatch
```
That contrast is the whole point of splitting passes.

### Prompt 3 — review a 12+ file PR with split passes and structured output
```powershell
powershell -File pipeline/review-pipeline.ps1 -BaseRef main -HeadRef HEAD
```
Reviews all 15 changed files via both passes and emits structured findings:

```json
{
  "file": "src/db.js", "line": 16, "severity": "critical", "pass": "per-file",
  "issue": "userId is concatenated directly into the SQL string, allowing SQL injection.",
  "suggested_fix": "Use a parameterized query: driver.query('... WHERE user_id = ?', [userId])."
}
```
Full results land in [`findings/findings.json`](findings/) and `findings/report.md`.

---

## What's in the sample PR (`feature/loyalty-checkout`)

15 changed files: a mix of **real bugs** (must be flagged), **cosmetic nits** (must
be skipped), and **cross-file contract breaks** (only the cross-file pass can see).

| File                 | Planted real bug(s)                                  | Severity   | Pass       |
|----------------------|------------------------------------------------------|------------|------------|
| `src/auth.js`        | empty-token auth bypass; weak RNG; session leak      | crit/high/med | per-file |
| `src/db.js`          | SQL injection via string concatenation               | critical   | per-file   |
| `src/api.js`         | untrusted `req.query` into the SQL builder           | high       | per-file   |
| `src/orders.js`      | uninitialized accumulator → every total is `NaN`     | high       | per-file   |
| `src/inventory.js`   | `> 0` instead of `>= qty`; oversell / negative stock | high       | per-file   |
| `src/discount.js`    | returns the discount amount, not the discounted price| high       | per-file   |
| `src/payment.js`     | swallowed charge error; gateway leak on error path   | high/med   | per-file   |
| `src/validation.js`  | `parseInt` drops cents; negative prices accepted     | medium     | per-file   |
| `src/cache.js`       | unbounded cache (no eviction/TTL)                    | medium     | per-file   |
| `src/notifications.js`| fire-and-forget promise → unhandled rejection       | medium     | per-file   |
| `src/loyalty.js`     | `>` vs `>=` tier off-by-one                          | medium     | per-file   |
| `src/config.js`      | hardcoded payment API key default                    | medium     | per-file   |
| `src/utils.js`       | (clean locally — signature change bites elsewhere)   | —          | —          |
| `src/logger.js`      | **only cosmetic nits — correctly returns `[]`**      | —          | (skipped)  |
| `src/index.js`       | wiring only — clean                                  | —          | —          |
| **cross-file**       | `formatPrice` signature change vs 2 one-arg callers; `DB_TIMEOUT`→`DATABASE_TIMEOUT` rename vs 2 stale readers | high/med | cross-file |

`logger.js` is the proof-of-precision file: it is full of `var`, missing semicolons,
inconsistent spacing, a leftover `console.log`, and a TODO — and the reviewer returns
**no findings**, because none of that is a real defect.

---

## How it works in CI

[`.github/workflows/code-review.yml`](.github/workflows/code-review.yml) runs on every
PR: checks out full history, installs the Claude Code CLI, runs
`pipeline/review-pipeline.sh` (authenticating via the `ANTHROPIC_API_KEY` secret),
uploads `findings/` as an artifact, posts the findings as a PR comment, and fails the
check when blocking issues exist. Because everything uses `claude -p`, the job can
never hang.

---

## Repo layout

```
CLAUDE.md                      team review standards (auto-loaded by claude)
pipeline/
  review-pipeline.ps1          orchestrator (Windows / primary)
  review-pipeline.sh           orchestrator (Linux / CI)
  prompts/per-file.md          per-file pass prompt (criteria + few-shot + JSON)
  prompts/cross-file.md        cross-file pass prompt
  mock-findings.json           canned reviewer output for -Mock (no API calls)
prompt-evolution/              v1 -> v2 -> v3 staged prompt refinement
src/                           the sample app (buggy PR on feature/loyalty-checkout)
.github/workflows/             the CI integration
findings/                      generated output (gitignored)
```

## Pipeline options

| flag (`.ps1`)     | env (`.sh`)    | default | meaning                                    |
|-------------------|----------------|---------|--------------------------------------------|
| `-BaseRef`        | `BASE`         | `main`  | diff base                                  |
| `-HeadRef`        | `HEAD`         | `HEAD`  | diff head                                  |
| `-Mock`           | —              | off     | use canned findings, no API calls          |
| `-SinglePass`     | `SINGLE_PASS=1`| off     | per-file only; skip the cross-file pass    |
| `-ComparePasses`  | —              | off     | print per-file vs cross-file comparison    |
| `-FailOn`         | `FAIL_ON`      | `high`  | severity that makes the run exit non-zero  |

## Definition of done — verified

- [x] Pipeline runs without hanging (every call uses `claude -p`).
- [x] Refined prompt flags real issues, skips nits (`logger.js` → `[]`; `auth.js` →
      the bypass, not the quote style).
- [x] A 15-file change gets consistent feedback via split passes.
- [x] Findings come out structured (`{file, line, severity, issue, suggested_fix}`).
