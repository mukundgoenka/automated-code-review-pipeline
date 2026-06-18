# Stage 3 — Add few-shot examples + structured JSON output (production)

The full text lives in [`../pipeline/prompts/per-file.md`](../pipeline/prompts/per-file.md).
The two ideas this stage adds:

## 1. Few-shot examples calibrate the fuzzy boundary

Telling the model "ignore cosmetic issues" is abstract. *Showing* it one file that
should produce a finding and one that should produce `[]` makes the boundary
concrete:

- A `try { charge() } catch (e) {}` → **one `high` finding** (swallowed error).
- A file with only `var`, bad spacing, missing semicolons → **`[]`**.

After seeing these, the model stops hedging on borderline cases. Precision goes up
*and* recall on real bugs goes up, because the examples show it what "real" looks
like.

## 2. Strict JSON output makes it pipeline-ready

```
[{ "file": "...", "line": 14, "severity": "high",
   "issue": "...", "suggested_fix": "..." }]
```

Now the pipeline can `JSON.parse` the result and post each element as an inline PR
comment. Prose like "[high] line 14 ..." can't be parsed reliably; JSON can.

## The measurable progression (on this repo's sample PR)

| stage | prompt                | findings on `logger.js` | real bugs missed | machine-postable |
|-------|-----------------------|-------------------------|------------------|------------------|
| v1    | "what's wrong?"       | 6 (all cosmetic)        | —                | no               |
| v2    | + criteria + severity | 0                       | a few borderline | no (prose)       |
| v3    | + few-shot + JSON     | 0                       | ~0               | yes (JSON)       |

The lesson: **explicit criteria kill false positives; few-shot examples calibrate
the edge cases; a JSON contract makes it automatable.** That is exactly what
`pipeline/prompts/per-file.md` and `cross-file.md` encode.
