#!/usr/bin/env bash
# run-scaffold-determinism.sh — zero-token determinism check for the
# token-optimized skill. Runs scaffold.sh TWICE with the same answers file and
# compares the two charts. No agent/LLM involved, so this is a true unit test of
# the generator's determinism (expect 100% identical).
#
# Usage:
#   ./run-scaffold-determinism.sh [--answers <file>] [--chart-name <name>] [--threshold 100]
#
# Defaults to the skill's answers.example.env (chart: orders-api).

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
SCAFFOLD="$SKILL/scaffold.sh"

ANSWERS="$SKILL/answers.example.env"
CHART_NAME="orders-api"
THRESHOLD=100
OUTROOT="${TMPDIR:-/tmp}/helm-scaffold-determinism"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers)    ANSWERS="$2"; shift 2;;
    --chart-name) CHART_NAME="$2"; shift 2;;
    --threshold)  THRESHOLD="$2"; shift 2;;
    --outroot)    OUTROOT="$2"; shift 2;;
    -h|--help)    sed -n '2,14p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -f "$SCAFFOLD" ]] || { echo "ERROR: scaffold.sh not found at $SCAFFOLD" >&2; exit 2; }
[[ -f "$ANSWERS" ]]  || { echo "ERROR: answers file not found: $ANSWERS" >&2; exit 2; }

rm -rf "$OUTROOT"; mkdir -p "$OUTROOT/run1" "$OUTROOT/run2"
echo ">>> scaffold run 1"; bash "$SCAFFOLD" --answers "$ANSWERS" --out "$OUTROOT/run1" >/dev/null
echo ">>> scaffold run 2"; bash "$SCAFFOLD" --answers "$ANSWERS" --out "$OUTROOT/run2" >/dev/null

echo "### Comparing run1 vs run2"
"$HERE/compare-charts.sh" "$OUTROOT/run1/$CHART_NAME" "$OUTROOT/run2/$CHART_NAME" "$THRESHOLD"
status=$?

# --- Render every overlay (catches an overlay that breaks templating) ---------
# helm-gated: skips cleanly on runners without helm so the core determinism
# check stays dependency-free.
CHART1="$OUTROOT/run1/$CHART_NAME"
if command -v helm >/dev/null 2>&1; then
  echo
  echo "### helm template — base + each overlay (run1)"
  for vals in values.yaml values-dev.yaml values-uat.yaml values-prod.yaml; do
    echo "  - rendering with $vals"
    if ! helm template "$CHART1" -f "$CHART1/$vals" >/dev/null; then
      echo "FAIL ❌  helm template with $vals"; status=1
    fi
  done
  [[ "$status" -eq 0 ]] && echo "  all overlays render."
else
  echo
  echo "(helm not installed — overlay rendering skipped; determinism check still ran.)"
fi

exit "$status"
