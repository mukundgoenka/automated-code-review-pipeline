# Stage 1 — Broad prompt (the naive baseline)

```
Review this file and tell me what's wrong with it.
```

## Why we start here

This is what most people type first. It "works" in the sense that it produces
output — but the output is noisy.

## What actually happens on `src/logger.js` (a file with only style issues)

```
1. Consider using `const` instead of `var` on line 3.
2. Add semicolons at the end of statements (lines 4, 7, 9).
3. The function name `f` is not descriptive — rename to something clearer.
4. There's a leftover console.log on line 11 you may want to remove.
5. Consider using template literals instead of string concatenation.
6. The comment on line 1 is redundant.
```

**Six comments, zero real bugs.** Every one is a linter/formatter job. In a PR this
is pure noise — reviewers learn to ignore the bot, and the one time it has something
real to say, nobody reads it.

Problems with the broad prompt:
- No definition of "wrong" → the model defaults to listing *everything*.
- No severity → a missing semicolon looks as important as an auth bypass.
- No output structure → can't be posted as PR comments automatically.
- No "stay silent" instruction → it always finds *something*.

➡️ Next: [v2-criteria.md](v2-criteria.md) adds explicit criteria and a severity rubric.
