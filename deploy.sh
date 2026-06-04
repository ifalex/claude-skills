#!/usr/bin/env bash
#
# deploy.sh — copy skills from this repo into an agent's skills directory.
#
# This repo is the source of truth. Edit skills under ./skills/, then run this
# script to publish them to Claude Code and/or GitHub Copilot CLI.
#
# Usage:
#   ./deploy.sh                      # deploy ALL skills to Claude Code (~/.claude/skills)
#   ./deploy.sh helm-chart-creator   # deploy one skill to Claude Code
#   ./deploy.sh --target copilot     # deploy ALL skills to Copilot CLI (~/.copilot/skills)
#   ./deploy.sh --target all         # deploy to BOTH Claude Code and Copilot CLI
#   ./deploy.sh --target all foo bar # deploy named skills to both
#   ./deploy.sh --dry-run            # show what would happen, change nothing
#
# Targets:
#   claude   -> ~/.claude/skills   (override with CLAUDE_SKILLS_DIR)
#   copilot  -> ~/.copilot/skills  (override with COPILOT_SKILLS_DIR)
#   all      -> both of the above

set -euo pipefail

REPO_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
SKILLS_SRC="$REPO_DIR/skills"

CLAUDE_SKILLS_DIR="${CLAUDE_SKILLS_DIR:-$HOME/.claude/skills}"
COPILOT_SKILLS_DIR="${COPILOT_SKILLS_DIR:-$HOME/.copilot/skills}"

target="claude"
dry_run=false
names=()

while [[ $# -gt 0 ]]; do
  case "$1" in
    --target) target="${2:?--target needs a value: claude|copilot|all}"; shift 2 ;;
    --dry-run) dry_run=true; shift ;;
    -h|--help) sed -n '2,30p' "${BASH_SOURCE[0]}" | sed 's/^# \{0,1\}//'; exit 0 ;;
    -*) echo "Unknown flag: $1" >&2; exit 2 ;;
    *) names+=("$1"); shift ;;
  esac
done

case "$target" in
  claude)  dests=("$CLAUDE_SKILLS_DIR") ;;
  copilot) dests=("$COPILOT_SKILLS_DIR") ;;
  all)     dests=("$CLAUDE_SKILLS_DIR" "$COPILOT_SKILLS_DIR") ;;
  *) echo "Invalid --target '$target' (use claude|copilot|all)" >&2; exit 2 ;;
esac

# Default to every skill directory in the repo.
if [[ ${#names[@]} -eq 0 ]]; then
  for d in "$SKILLS_SRC"/*/; do names+=("$(basename "$d")"); done
fi

copy_one() {
  local name="$1" dest_root="$2"
  local src="$SKILLS_SRC/$name"
  local dest="$dest_root/$name"
  if [[ ! -d "$src" ]]; then echo "  ! skill not found: $name (skipping)" >&2; return 1; fi
  if $dry_run; then echo "  [dry-run] $src -> $dest"; return 0; fi
  mkdir -p "$dest_root"
  rm -rf "$dest"
  cp -R "$src" "$dest"
  echo "  ✓ $name -> $dest"
}

for dest_root in "${dests[@]}"; do
  echo "Deploying to: $dest_root"
  for name in "${names[@]}"; do
    copy_one "$name" "$dest_root" || true
  done
done

echo "Done."
