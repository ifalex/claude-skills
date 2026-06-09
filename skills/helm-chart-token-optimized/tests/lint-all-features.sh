#!/usr/bin/env bash
# lint-all-features.sh — schema <-> values coverage check (B3).
#
# Scaffolds a chart with EVERY toggle enabled (answers.all-features.env) so all
# conditional templates and all schema-validated values are present, then runs
# `helm lint` (which validates values.yaml against values.schema.json) and
# `helm template`. A value that exists in values.yaml but is missing/contradicted
# in the schema — or a template that breaks when its feature is on — surfaces
# here instead of in a user's chart.
#
# Requires `helm`. If helm is not installed the test SKIPS (exit 0) with a clear
# message, so it stays CI-friendly on minimal runners.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
SCAFFOLD="$SKILL/scaffold.sh"
ANSWERS="$HERE/answers.all-features.env"
CHART_NAME="all-features"
OUTROOT="${TMPDIR:-/tmp}/helm-all-features"

[[ -f "$SCAFFOLD" ]] || { echo "ERROR: scaffold.sh not found: $SCAFFOLD" >&2; exit 2; }
[[ -f "$ANSWERS" ]]  || { echo "ERROR: answers file not found: $ANSWERS" >&2; exit 2; }

if ! command -v helm >/dev/null 2>&1; then
  echo "SKIP ⚠️  helm not installed — schema/values lint not run."
  echo "        install helm to exercise this check (brew install helm)."
  exit 0
fi

rm -rf "$OUTROOT"; mkdir -p "$OUTROOT"
echo ">>> scaffold all-features chart"
bash "$SCAFFOLD" --answers "$ANSWERS" --out "$OUTROOT" >/dev/null || {
  echo "FAIL ❌  scaffold.sh failed on the all-features answers" >&2; exit 1; }

CHART="$OUTROOT/$CHART_NAME"
status=0

echo "### helm lint (validates values.yaml against values.schema.json)"
if helm lint "$CHART"; then echo "  lint ok"; else echo "FAIL ❌  helm lint"; status=1; fi

echo "### helm template (base + each overlay)"
for vals in values.yaml values-dev.yaml values-uat.yaml values-prod.yaml; do
  echo "  - rendering with $vals"
  if ! helm template "$CHART" -f "$CHART/$vals" >/dev/null; then
    echo "FAIL ❌  helm template with $vals"; status=1
  fi
done

if [[ "$status" -eq 0 ]]; then
  echo "PASS ✅  all features render and validate against the schema"
fi
exit "$status"
