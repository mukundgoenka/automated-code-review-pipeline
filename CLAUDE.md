# ShopLine Engineering — Project Context & Code Review Standards

This file is auto-loaded by Claude Code on every run inside this repo. It is the
**single source of truth** for what our automated reviewer cares about. Change the
rules here and every review — per-file and cross-file — follows the new rules.

## What this service is

`shopline-orders-api` is the checkout, inventory, and loyalty backend. It handles
money, stock, and customer auth, so **correctness and security bugs are expensive**.
Cosmetic inconsistency is not.

## Review philosophy (read before flagging anything)

We optimize for **precision, not recall of nitpicks**. A review that flags 20 style
issues and misses one auth bypass is a failed review. When in doubt, stay silent.

- **Flag** something only if a competent engineer would agree it is a real defect.
- **Do not flag** anything whose worst outcome is "slightly less pretty."
- One finding per distinct root cause. Do not restate the same bug three ways.

## DO flag (real issues)

- **Security**: injection (SQL/command/path), auth/authz bypass, secrets in code,
  unsafe deserialization, missing input validation on a trust boundary.
- **Correctness**: wrong logic, off-by-one, inverted conditions, `NaN`/`undefined`
  propagation, incorrect money/stock math, wrong operator.
- **Resource & reliability**: leaks (connections, file handles, unbounded caches),
  swallowed errors, unhandled promise rejections, race conditions / check-then-act.
- **Contract breaks** (cross-file): a changed function signature, renamed/removed
  export, or renamed config key whose call sites were not updated.
- **Data loss / corruption**: anything that can write bad or partial state.

## DO NOT flag (cosmetic — out of scope)

These are handled by our linter/formatter (ESLint + Prettier run in a separate CI
job). The reviewer must stay silent on them:

- Naming style, abbreviations, `var` vs `const` when behavior is unchanged.
- Quote style, semicolons, indentation, blank lines, trailing whitespace.
- Comment wording, TODO comments, leftover `console.log` (unless it leaks secrets).
- Subjective "I would have structured this differently" preferences.
- Micro-optimizations with no measurable impact.

## Severity rubric (use these exact values)

| severity   | meaning                                                              |
|------------|---------------------------------------------------------------------|
| `critical` | exploitable security hole or guaranteed data/money loss in prod      |
| `high`     | wrong result for real inputs, or crash on a common path              |
| `medium`   | wrong result on an edge case, leak, or reliability risk under load   |
| `low`      | real but minor; safe to merge, fix soon (NOT cosmetic — see above)   |

If your only candidates are cosmetic, return an empty finding list. That is a
**successful** review, not an empty one.

## Testing standards

- Money and stock math must have unit tests covering zero, negative, and overflow.
- Anything touching auth must have a test for the unauthenticated/empty-token path.
- New modules should not be merged without at least one test exercising the happy
  path. Flag *missing tests* only for security- or money-critical new logic.

## Output contract

Every reviewer pass returns findings as a JSON array (see `pipeline/prompts/`).
Each finding: `{ "file", "line", "severity", "issue", "suggested_fix" }`.
Return `[]` when there is nothing real to report.
