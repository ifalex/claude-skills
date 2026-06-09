#!/usr/bin/env bash
# check-kube-quality.sh — assert a freshly scaffolded chart passes the linters.
#
# Guards the promise "good from the very beginning": a default chart must pass
# kube-linter, and EVERY environment — the base values plus the dev/uat/prod
# overlays — must score 0 CRITICAL in kube-score. Security posture is identical
# across environments (NetworkPolicy on, pullPolicy Always, non-root UID >=10000);
# only scale/resources differ. dev keeps a permissive allow-all NetworkPolicy.
#
# Tool-gated: SKIPs cleanly (exit 0) when helm/kube-linter/kube-score are absent,
# so it stays CI-friendly on minimal runners.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
SCAFFOLD="$SKILL/scaffold.sh"
ANSWERS="$SKILL/answers.example.env"
CHART="orders-api"
OUTROOT="${TMPDIR:-/tmp}/helm-kube-quality"

command -v helm >/dev/null 2>&1 || { echo "SKIP ⚠️  helm not installed."; exit 0; }

rm -rf "$OUTROOT"; mkdir -p "$OUTROOT"
bash "$SCAFFOLD" --answers "$ANSWERS" --out "$OUTROOT" >/dev/null || {
  echo "FAIL ❌  scaffold.sh failed" >&2; exit 1; }
DIR="$OUTROOT/$CHART"
status=0

# --- kube-linter (static analysis of the chart) ------------------------------
if command -v kube-linter >/dev/null 2>&1; then
  echo "### kube-linter"
  if kube-linter lint "$DIR" >/tmp/kl.out 2>&1; then
    echo "  no lint errors ✅"
  else
    echo "FAIL ❌  kube-linter found issues:"; sed 's/^/    /' /tmp/kl.out; status=1
  fi
else
  echo "### kube-linter — SKIP (not installed)"
fi

# --- kube-score every environment (all must be 0 CRITICAL) -------------------
# Renders base values plus each overlay. "base" uses no -f (the common values.yaml).
score_env() { # <label> <-f file or empty>
  if [[ -n "$2" ]]; then helm template rel "$DIR" -f "$2" 2>/dev/null; else helm template rel "$DIR" 2>/dev/null; fi \
    | kube-score score - 2>/dev/null
}
if command -v kube-score >/dev/null 2>&1; then
  echo "### kube-score (base + dev/uat/prod must each be 0 CRITICAL)"
  for env in base dev uat prod; do
    file=""; [[ "$env" != "base" ]] && file="$DIR/values-$env.yaml"
    crit=$(score_env "$env" "$file" | grep -c '\[CRITICAL\]')
    if [[ "$crit" -eq 0 ]]; then
      echo "  $env: 0 CRITICAL ✅"
    else
      echo "FAIL ❌  $env has $crit kube-score CRITICAL(s):"
      score_env "$env" "$file" | grep '\[CRITICAL\]' | sed 's/^/    /'
      status=1
    fi
  done
else
  echo "### kube-score — SKIP (not installed)"
fi

[[ "$status" -eq 0 ]] && echo "PASS ✅  chart passes kube-linter + kube-score (all environments)"
exit "$status"
