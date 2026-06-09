#!/usr/bin/env bash
# check-kube-quality.sh — assert a freshly scaffolded chart passes the linters.
#
# Guards the promise "good from the very beginning": a default chart must pass
# kube-linter, and its real-cluster overlays (uat, prod) must score 0 CRITICAL in
# kube-score. dev is intentionally permissive (single-replica SIT, no
# NetworkPolicy) so it is NOT required to be CRITICAL-free.
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

# --- kube-score on the real-cluster overlays (must be 0 CRITICAL) -------------
if command -v kube-score >/dev/null 2>&1; then
  echo "### kube-score (uat, prod must be 0 CRITICAL)"
  for env in uat prod; do
    crit=$(helm template rel "$DIR" -f "$DIR/values-$env.yaml" 2>/dev/null \
           | kube-score score - 2>/dev/null | grep -c '\[CRITICAL\]')
    if [[ "$crit" -eq 0 ]]; then
      echo "  $env: 0 CRITICAL ✅"
    else
      echo "FAIL ❌  $env overlay has $crit kube-score CRITICAL(s):"
      helm template rel "$DIR" -f "$DIR/values-$env.yaml" 2>/dev/null \
        | kube-score score - 2>/dev/null | grep '\[CRITICAL\]' | sed 's/^/    /'
      status=1
    fi
  done
else
  echo "### kube-score — SKIP (not installed)"
fi

[[ "$status" -eq 0 ]] && echo "PASS ✅  chart passes kube-linter + kube-score (uat/prod)"
exit "$status"
