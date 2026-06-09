#!/usr/bin/env bash
# check-defaults-parity.sh — keep the answer-file and the scaffold in sync (B2).
#
# Defaults/keys live in two machine-read places that MUST agree:
#   - answers.example.env   (the keys a user fills in)
#   - scaffold.sh           (the variables it initialises in its Defaults block)
# If a key is renamed in one but not the other, the user's value silently stops
# taking effect. This asserts the two key sets are identical (both directions).
#
# Note: explanations.md also documents defaults in prose. That free-text is
# reviewed by humans, not asserted here (parsing prose defaults is brittle and
# would make this guard flaky) — keep it in step manually when a default changes.
#
# Pure text, no model/helm. Exits non-zero on drift.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL="$(cd "$HERE/.." && pwd)"
EXAMPLE="$SKILL/answers.example.env"
SCAFFOLD="$SKILL/scaffold.sh"

[[ -f "$EXAMPLE" ]]  || { echo "ERROR: answers.example.env not found: $EXAMPLE" >&2; exit 2; }
[[ -f "$SCAFFOLD" ]] || { echo "ERROR: scaffold.sh not found: $SCAFFOLD" >&2; exit 2; }

TMP_EX=$(mktemp); TMP_SC=$(mktemp)
trap 'rm -f "$TMP_EX" "$TMP_SC"' EXIT

# Keys assigned in answers.example.env (strip comments/blank lines).
grep -oE '^[A-Z0-9_]+=' "$EXAMPLE" | sed 's/=$//' | sort -u > "$TMP_EX"

# Variables scaffold.sh initialises in its Defaults block. They sit between the
# "Defaults" banner and the line that sources the answers file (`. "$ANSWERS"`),
# as `NAME="..."` (possibly several per line).
awk '
  /^# --- Defaults/ {grab=1; next}
  /^\. "\$ANSWERS"/ {grab=0}
  grab {
    while (match($0, /[A-Z0-9_]+=/)) {
      print substr($0, RSTART, RLENGTH-1)
      $0 = substr($0, RSTART+RLENGTH)
    }
  }
' "$SCAFFOLD" | sort -u > "$TMP_SC"

only_example=$(comm -23 "$TMP_EX" "$TMP_SC")
only_scaffold=$(comm -13 "$TMP_EX" "$TMP_SC")

status=0
if [[ -n "$only_example" ]]; then
  status=1
  echo "FAIL ❌  keys in answers.example.env that scaffold.sh does NOT recognise"
  echo "        (user sets them but they have no effect):"
  printf '          - %s\n' $only_example
fi
if [[ -n "$only_scaffold" ]]; then
  status=1
  echo "FAIL ❌  scaffold.sh default vars missing from answers.example.env"
  echo "        (undocumented knobs — add them to the example):"
  printf '          - %s\n' $only_scaffold
fi

if [[ "$status" -eq 0 ]]; then
  n=$(grep -c . "$TMP_EX")
  echo "PASS ✅  defaults parity: $n keys identical in answers.example.env and scaffold.sh"
fi
exit "$status"
