#!/usr/bin/env bash
# check-deployed-sync.sh — warn when a DEPLOYED copy of this skill lags the repo (C3).
#
# The repo (./skills/...) is the source of truth; deploy.sh publishes it to an
# agent's skills dir. If the deployed copy drifts (someone edits the repo but
# forgets to re-run deploy.sh), the agent runs stale instructions — which is how
# the original token blow-up happened. This diffs the deployed copy against the
# repo for THIS skill.
#
# Checks the same destinations deploy.sh writes to (override via env):
#   CLAUDE_SKILLS_DIR  (default ~/.claude/skills)
#   COPILOT_SKILLS_DIR (default ~/.copilot/skills)
# Or pass an explicit dir:  --deployed /path/to/skills-root
#
# Behaviour: if no deployed copy is found anywhere, SKIP (exit 0) — you simply
# haven't deployed. If a deployed copy exists and differs, FAIL (exit 1) unless
# --warn-only is given. Generated test output (run*/) is ignored.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"
SKILL_SRC="$(cd "$HERE/.." && pwd)"
SKILL_NAME="$(basename "$SKILL_SRC")"

WARN_ONLY=0
EXPLICIT=""
while [[ $# -gt 0 ]]; do
  case "$1" in
    --deployed)  EXPLICIT="$2"; shift 2;;
    --warn-only) WARN_ONLY=1; shift;;
    -h|--help)   sed -n '2,22p' "$0"; exit 0;;
    *) echo "unknown arg: $1" >&2; exit 2;;
  esac
done

roots=()
if [[ -n "$EXPLICIT" ]]; then
  roots+=("$EXPLICIT")
else
  roots+=("${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}")
  roots+=("${COPILOT_SKILLS_DIR:-$HOME/.copilot/skills}")
fi

found=0
drift=0
for root in "${roots[@]}"; do
  dep="$root/$SKILL_NAME"
  [[ -d "$dep" ]] || continue
  found=1
  echo "### Deployed copy: $dep"
  # Compare recursively; ignore generated determinism output and VCS noise.
  out=$(diff -r \
        --exclude='run*' \
        --exclude='helm-determinism-runs' \
        --exclude='helm-scaffold-determinism' \
        --exclude='.git' \
        "$SKILL_SRC" "$dep" 2>&1)
  if [[ -z "$out" ]]; then
    echo "  in sync ✅"
  else
    drift=1
    echo "  DRIFT ⚠️  deployed copy differs from repo:"
    printf '%s\n' "$out" | sed 's/^/    /'
    echo "  → re-run: ./deploy.sh $SKILL_NAME"
  fi
done

if [[ "$found" -eq 0 ]]; then
  echo "SKIP ⚠️  no deployed copy of '$SKILL_NAME' found (checked: ${roots[*]})."
  echo "        nothing to compare — deploy with ./deploy.sh $SKILL_NAME if you intend to run it."
  exit 0
fi

if [[ "$drift" -eq 0 ]]; then
  echo "PASS ✅  deployed copy matches the repo."
  exit 0
fi
[[ "$WARN_ONLY" -eq 1 ]] && { echo "(warn-only: not failing)"; exit 0; }
echo "FAIL ❌  deployed skill is stale — re-deploy before trusting a run."
exit 1
