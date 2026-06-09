#!/usr/bin/env bash
# check-placeholder-parity.sh — zero-token guard for the scaffold renderer.
#
# Every `%%PLACEHOLDER%%` in reference/templates/values.yaml.tmpl MUST have a
# matching `add PLACEHOLDER ...` line in scaffold.sh, and vice versa. If the two
# sets ever diverge, the symptom is a literal `%%X%%` shipping in a user's
# values.yaml (placeholder never substituted) or a dead `add` line. This catches
# that at commit time instead of in a generated chart.
#
# No model, no helm, no network — pure text comparison. Exits non-zero on drift.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
TMPL="$SKILL/reference/templates/values.yaml.tmpl"
SCAFFOLD="$SKILL/scaffold.sh"

[[ -f "$TMPL" ]]     || { echo "ERROR: template not found: $TMPL" >&2; exit 2; }
[[ -f "$SCAFFOLD" ]] || { echo "ERROR: scaffold.sh not found: $SCAFFOLD" >&2; exit 2; }

TMP_TPL=$(mktemp); TMP_SED=$(mktemp)
trap 'rm -f "$TMP_TPL" "$TMP_SED"' EXIT

# Placeholders referenced by the template (unique, sorted).
grep -oE '%%[A-Z0-9_]+%%' "$TMPL" | sed 's/%%//g' | sort -u > "$TMP_TPL"
# Placeholders the scaffold knows how to substitute (its `add NAME ...` lines).
grep -oE '^add[[:space:]]+[A-Z0-9_]+' "$SCAFFOLD" | awk '{print $2}' | sort -u > "$TMP_SED"

missing_in_scaffold=$(comm -23 "$TMP_TPL" "$TMP_SED")
missing_in_tmpl=$(comm -13 "$TMP_TPL" "$TMP_SED")

status=0
if [[ -n "$missing_in_scaffold" ]]; then
  status=1
  echo "FAIL ❌  template placeholders with NO matching 'add' in scaffold.sh"
  echo "        (these would ship as literal %%X%% in values.yaml):"
  printf '          - %%%%%s%%%%\n' $missing_in_scaffold
fi
if [[ -n "$missing_in_tmpl" ]]; then
  status=1
  echo "FAIL ❌  scaffold 'add' lines with NO matching placeholder in the template"
  echo "        (dead substitutions — remove or fix the name):"
  printf '          - %s\n' $missing_in_tmpl
fi

if [[ "$status" -eq 0 ]]; then
  n=$(grep -c . "$TMP_TPL")
  echo "PASS ✅  placeholder parity: all $n placeholders matched in both directions"
fi
exit "$status"
