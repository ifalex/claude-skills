#!/usr/bin/env bash
# check-interview-gate.sh — behavioral test for the Step 0 interview gate.
#
# This is the COMPLEMENT to run-determinism.sh. That one front-loads every answer
# and measures OUTPUT determinism. This one does the opposite: it sends a prompt
# with NO interview answers and asserts the skill HOLDS THE GATE — i.e. it asks
# first and writes NOTHING. The prompt deliberately "looks complete" (image+port)
# because that is the exact rationalization the skill's Red Flags table targets
# ("the prompt already gave me enough to start").
#
# Unlike the no-model guards in run-all.sh, this REQUIRES a model — the gate is a
# behavioral property of the skill instructions, not of scaffold.sh. Per the
# writing-skills (skill-creator) methodology this is a GREEN-phase compliance
# check. The baseline model is the realistic target tier (Sonnet), NOT a weak
# model — a weak model failing the gate is a capability signal, not a skill bug.
#
# ---------------------------------------------------------------------------
# THE CONTRACT your --driver command must satisfy (same as run-determinism.sh):
#   1. It READS THE PROMPT ON STDIN.
#   2. It runs NON-INTERACTIVELY with file edits auto-approved.
#   3. It writes any files UNDER THE CURRENT WORKING DIRECTORY (we cd into a
#      fresh, empty run dir before invoking you).
# In print/non-interactive mode the agent cannot receive answers, so a
# correctly-gated skill will emit its interview questions and exit having
# written nothing — which is exactly PASS.
# ---------------------------------------------------------------------------
#
# Usage:
#   ./check-interview-gate.sh --driver '<cli invocation reading stdin>' \
#                             [--prompt gate-bare.prompt.txt] \
#                             [--outdir <dir>]
#
# Baseline driver (Sonnet target tier — verify flags against your CLI version):
#   ./check-interview-gate.sh --driver 'claude -p --model sonnet --permission-mode acceptEdits'
#
# Other harnesses (same stdin contract):
#   Copilot CLI : --driver 'copilot -p --allow-all-tools'
#   Gemini CLI  : --driver 'gemini -y'
#   Codex       : --driver 'codex exec --full-auto -'
#
# Exit codes: 0 = gate held (PASS), 1 = gate breached or could not confirm a
# question was asked (FAIL), 2 = usage error.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVER=""
PROMPT="$HERE/gate-bare.prompt.txt"
OUTDIR="${TMPDIR:-/tmp}/helm-gate-check"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver) DRIVER="$2"; shift 2;;
    --prompt) PROMPT="$2"; shift 2;;
    --outdir) OUTDIR="$2"; shift 2;;
    -h|--help) sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$DRIVER" ]] || { echo "ERROR: --driver is required (see --help)" >&2; exit 2; }
[[ -f "$PROMPT" ]] || { echo "ERROR: prompt file not found: $PROMPT" >&2; exit 2; }

echo "Driver : $DRIVER"
echo "Prompt : $PROMPT"
echo "Outdir : $OUTDIR"
echo

rm -rf "$OUTDIR"; mkdir -p "$OUTDIR"
log="$OUTDIR/agent.out"

# Contract: driver reads prompt on stdin, writes any files under cwd.
( cd "$OUTDIR" && eval "$DRIVER" < "$PROMPT" ) >"$log" 2>&1 \
  || echo "NOTE: driver returned non-zero (expected when the agent stops to ask) — continuing checks"

# --- Assertion 1: the gate held — NO chart files were written -----------------
written="$(find "$OUTDIR" -name Chart.yaml -o -name values.yaml -o -name 'values-*.yaml' 2>/dev/null | grep -v "$(basename "$log")" || true)"
if [[ -n "$written" ]]; then
  echo "FAIL: gate breached — the skill wrote files before any interview answer:"
  echo "$written" | sed 's/^/    /'
  echo
  echo "    Expected: zero files written until the user answers Step 0."
  echo "    See SKILL.md 'Step 0' and the Red Flags table."
  exit 1
fi

# --- Assertion 2: it actually ASKED (not just silently did nothing) ------------
# Look for interview signals from Step 0 / the essentials block.
if grep -qiE 'app name|workload|container port|generate now|review the full list|paste a filled answer|ingress|persistence|\?' "$log"; then
  echo "PASS: gate held — no files written and the skill asked the Step 0 interview."
  echo "      (agent output captured at $log)"
  exit 0
fi

echo "FAIL: no files written, but could not confirm the skill ASKED the interview."
echo "      It may have errored or produced nothing. Inspect: $log"
echo "      A pass requires BOTH: nothing written AND interview questions emitted."
exit 1
