# Stage 2 — Add explicit criteria + severity + "stay silent"

```
Review this file for REAL DEFECTS ONLY:
  - security (injection, auth bypass, secrets)
  - correctness (wrong logic, off-by-one, NaN/undefined, bad money/stock math)
  - reliability (leaks, swallowed errors, unhandled rejections, races)

Do NOT report cosmetic issues: naming, quotes, semicolons, formatting,
leftover console.logs, var vs const, TODO comments.

Assign each finding a severity: critical | high | medium | low.
If there are no real defects, say "No issues found." Do not invent nits.
```

## What changes

The model now has a **definition of "wrong"** and explicit permission to say
nothing. The same `src/logger.js` (style-only) now returns:

```
No issues found.
```

And on `src/payment.js` (which really does swallow payment errors):

```
[high] The catch block on line 14 swallows charge failures, so a failed payment
still returns success.
```

That's the signal we want. The false positives are gone.

## What's still missing

- The boundary between "real" and "cosmetic" is fuzzy in edge cases. The model
  occasionally still flags a borderline naming issue, or under-flags because it's
  not sure something counts.
- Output is prose, not machine-postable. We can't reliably parse `[high] ...` into
  PR comments.

➡️ Next: [v3-fewshot.md](v3-fewshot.md) pins down the boundary with examples and
fixes the output format.
