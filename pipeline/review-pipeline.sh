#!/usr/bin/env bash
# Automated PR code-review pipeline driven by Claude Code (non-interactive).
# Linux/CI counterpart of review-pipeline.ps1. Requires: git, jq, claude.
#
#   ./pipeline/review-pipeline.sh                 # per-file + cross-file on main...HEAD
#   BASE=main HEAD=HEAD ./pipeline/review-pipeline.sh
#   FAIL_ON=critical SINGLE_PASS=1 ./pipeline/review-pipeline.sh
#
# Every model call uses `claude -p` (print mode): it prints the result and exits,
# so the pipeline never waits for input and never hangs. Each call is a fresh,
# independent reviewer instance. `timeout` bounds any single call as a backstop.
set -euo pipefail

BASE="${BASE:-main}"
HEAD="${HEAD:-HEAD}"
PATTERN="${PATTERN:-\.js$}"
OUTDIR="${OUTDIR:-findings}"
FAIL_ON="${FAIL_ON:-high}"          # critical|high|medium|low|none
SINGLE_PASS="${SINGLE_PASS:-0}"
CALL_TIMEOUT="${CALL_TIMEOUT:-180}" # seconds per claude call

REPO_ROOT="$(cd "$(dirname "$0")/.." && pwd)"
PROMPTS="$REPO_ROOT/pipeline/prompts"
cd "$REPO_ROOT"
mkdir -p "$OUTDIR"

rank() { case "$1" in critical) echo 4;; high) echo 3;; medium) echo 2;; low) echo 1;; *) echo 0;; esac; }

# Run one fresh reviewer instance; echo a JSON array (or [] on any failure).
review() {  # $1 = prompt file ; stdin = payload
  local out
  if ! out="$(timeout "$CALL_TIMEOUT" claude -p "$(cat "$1")" 2>/dev/null)"; then
    echo "[]"; return 0
  fi
  # Strip code fences and keep the outermost [ ... ] so jq can parse it.
  out="$(printf '%s' "$out" | sed -E 's/^```[a-zA-Z]*//; s/```$//')"
  out="$(printf '%s' "$out" | sed -n '/\[/,/\]/p')"
  if printf '%s' "$out" | jq -e . >/dev/null 2>&1; then printf '%s' "$out"; else echo "[]"; fi
}

CHANGED="$(git diff --name-only "$BASE...$HEAD" | grep -E "$PATTERN" || true)"
if [ -z "$CHANGED" ]; then echo "No changed files to review."; exit 0; fi
echo "Reviewing $(echo "$CHANGED" | wc -l | tr -d ' ') changed file(s): $BASE...$HEAD"

ALL="[]"   # accumulated findings (JSON array)

echo "=== Pass 1 - per-file review ==="
while IFS= read -r rel; do
  [ -f "$rel" ] || continue
  payload="$(printf 'FILE: %s\n\n%s' "$rel" "$(cat "$rel")")"
  found="$(printf '%s' "$payload" | review "$PROMPTS/per-file.md")"
  found="$(printf '%s' "$found" | jq --arg p per-file 'map(. + {pass:$p})')"
  ALL="$(jq -s '.[0] + .[1]' <(printf '%s' "$ALL") <(printf '%s' "$found"))"
  echo "  $rel: $(printf '%s' "$found" | jq 'length') finding(s)"
done <<< "$CHANGED"

if [ "$SINGLE_PASS" != "1" ]; then
  echo "=== Pass 2 - cross-file review ==="
  payload=""
  while IFS= read -r rel; do
    [ -f "$rel" ] || continue
    payload="$payload"$'\n'"=== FILE: $rel ==="$'\n'"$(cat "$rel")"
  done <<< "$CHANGED"
  cross="$(printf '%s' "$payload" | review "$PROMPTS/cross-file.md")"
  cross="$(printf '%s' "$cross" | jq --arg p cross-file 'map(. + {pass:$p})')"
  ALL="$(jq -s '.[0] + .[1]' <(printf '%s' "$ALL") <(printf '%s' "$cross"))"
  echo "  $(printf '%s' "$cross" | jq 'length') cross-file finding(s)"
fi

# Aggregate
printf '%s' "$ALL" | jq '{total:length,
  critical:(map(select(.severity=="critical"))|length),
  high:(map(select(.severity=="high"))|length),
  medium:(map(select(.severity=="medium"))|length),
  low:(map(select(.severity=="low"))|length),
  findings:.}' > "$OUTDIR/findings.json"

echo "=== Summary ==="; jq -r '"critical \(.critical) | high \(.high) | medium \(.medium) | low \(.low) | total \(.total)"' "$OUTDIR/findings.json"
echo "Wrote $OUTDIR/findings.json"

# Exit non-zero if anything at/above FAIL_ON
if [ "$FAIL_ON" = "none" ]; then exit 0; fi
THRESH="$(rank "$FAIL_ON")"
BLOCK="$(printf '%s' "$ALL" | jq --argjson t "$THRESH" '[.[] | select((if .severity=="critical" then 4 elif .severity=="high" then 3 elif .severity=="medium" then 2 else 1 end) >= $t)] | length')"
if [ "$BLOCK" -gt 0 ]; then echo "FAIL: $BLOCK finding(s) at or above '$FAIL_ON'. Blocking merge."; exit 1; fi
echo "PASS: no findings at or above '$FAIL_ON'."
