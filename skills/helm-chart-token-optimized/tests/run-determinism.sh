#!/usr/bin/env bash
# run-determinism.sh — harness-neutral determinism runner for helm-chart-creator.
#
# Runs the SAME front-loaded prompt twice through whatever agent CLI you point it
# at (Claude Code, GitHub Copilot CLI, Gemini CLI, Codex, …), then compares the
# two generated charts with compare-charts.sh.
#
# ---------------------------------------------------------------------------
# THE CONTRACT your --driver command must satisfy (this is what makes it
# platform-agnostic — the runner knows nothing about your CLI):
#   1. It READS THE PROMPT ON STDIN.
#   2. It runs NON-INTERACTIVELY with file edits auto-approved.
#   3. It writes the chart UNDER THE CURRENT WORKING DIRECTORY (the runner cd's
#      into a fresh run dir before invoking you).
# ---------------------------------------------------------------------------
#
# Usage:
#   ./run-determinism.sh --driver '<cli invocation reading stdin>' \
#                        [--prompt scenario-a.prompt.txt] \
#                        [--chart-name orders-api] \
#                        [--threshold 95] \
#                        [--runs 2]
#
# Driver examples (VERIFY the exact flags against your installed CLI version —
# non-interactive/auto-approve flags change between releases):
#   Claude Code : --driver 'claude -p --permission-mode acceptEdits'
#   Copilot CLI : --driver 'copilot -p --allow-all-tools'      # or: copilot --prompt -
#   Gemini CLI  : --driver 'gemini -y'                         # -y = auto-approve
#   Codex       : --driver 'codex exec --full-auto -'
#
# Each of those reads the prompt from stdin. If your CLI takes the prompt as an
# ARGUMENT instead of stdin, wrap it so it still consumes stdin, e.g.:
#   --driver 'sh -c '\''copilot -p "$(cat)"'\'''
#
# Determinism dimensions this measures:
#   * Intra-platform (default): run1 vs run2 on the SAME CLI/model. Expect ≥95%.
#   * Cross-platform: generate run1 on platform X and run2 on platform Y (use
#     --skip-run and point compare-charts.sh at two dirs you produced separately).
#     Expect LOWER similarity — different models read the same skill differently.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
DRIVER=""
PROMPT="$HERE/scenario-a.prompt.txt"
CHART_NAME="orders-api"
THRESHOLD=95
RUNS=2
# Generated charts land OUTSIDE the repo by default so runs never pollute git.
# Override with --outroot to keep them somewhere else.
OUTROOT="${TMPDIR:-/tmp}/helm-determinism-runs"

while [[ $# -gt 0 ]]; do
  case "$1" in
    --driver)     DRIVER="$2"; shift 2;;
    --prompt)     PROMPT="$2"; shift 2;;
    --chart-name) CHART_NAME="$2"; shift 2;;
    --threshold)  THRESHOLD="$2"; shift 2;;
    --runs)       RUNS="$2"; shift 2;;
    --outroot)    OUTROOT="$2"; shift 2;;
    -h|--help)    sed -n '2,40p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$DRIVER" ]] || { echo "ERROR: --driver is required (see --help)" >&2; exit 2; }
[[ -f "$PROMPT" ]] || { echo "ERROR: prompt file not found: $PROMPT" >&2; exit 2; }
[[ "$RUNS" -ge 2 ]] || { echo "ERROR: need at least 2 runs to compare" >&2; exit 2; }

echo "Driver : $DRIVER"
echo "Prompt : $PROMPT"
echo "Runs   : $RUNS"
echo

# --- Execute the runs ---------------------------------------------------------
declare -a CHART_DIRS=()
for i in $(seq 1 "$RUNS"); do
  rundir="$OUTROOT/run$i"
  echo ">>> Run $i — fresh dir: $rundir"
  rm -rf "$rundir"; mkdir -p "$rundir"
  # Contract: driver reads prompt on stdin, writes chart under cwd.
  ( cd "$rundir" && eval "$DRIVER" < "$PROMPT" ) \
    || echo "WARN: driver returned non-zero on run $i (continuing to compare what exists)"
  chart="$rundir/$CHART_NAME"
  if [[ ! -d "$chart" ]]; then
    # Fall back to the first directory containing a Chart.yaml.
    chart="$(dirname "$(find "$rundir" -name Chart.yaml -print -quit 2>/dev/null)")"
  fi
  [[ -d "$chart" ]] || { echo "ERROR: run $i produced no chart dir under $rundir" >&2; exit 1; }
  CHART_DIRS+=("$chart")
  echo "    chart: $chart"
  echo
done

# --- Compare each run against run 1 ------------------------------------------
status=0
for j in $(seq 1 $((RUNS-1))); do
  echo "### Comparing run 1 vs run $((j+1))"
  "$HERE/compare-charts.sh" "${CHART_DIRS[0]}" "${CHART_DIRS[$j]}" "$THRESHOLD" || status=1
  echo
done

exit "$status"
