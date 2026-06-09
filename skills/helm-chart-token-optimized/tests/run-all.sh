#!/usr/bin/env bash
# run-all.sh — run every non-interactive guard for helm-chart-token-optimized.
#
# These need NO model. The helm-gated ones SKIP cleanly when helm is absent, so
# this is safe to run in CI on a minimal runner.
#
#   1. check-placeholder-parity.sh  — %%X%% in tmpl <-> `add X` in scaffold (C1)
#   2. check-defaults-parity.sh     — answers.example.env keys <-> scaffold (B2)
#   3. run-scaffold-determinism.sh  — scaffold twice, byte-compare (+overlays, C2)
#   4. lint-all-features.sh         — all toggles on, helm lint vs schema (B3)
#   5. check-kube-quality.sh        — kube-linter clean + kube-score 0 CRITICAL (uat/prod)
#
# check-deployed-sync.sh (C3) is intentionally NOT here — it inspects the local
# machine's deployed skill copy, which is environment-specific. Run it manually.

set -uo pipefail
HERE="$(cd "$(dirname "$0")" && pwd)"

tests=(
  "check-placeholder-parity.sh"
  "check-defaults-parity.sh"
  "run-scaffold-determinism.sh"
  "lint-all-features.sh"
  "check-kube-quality.sh"
)

status=0
for t in "${tests[@]}"; do
  echo "=================================================="
  echo ">>> $t"
  echo "=================================================="
  if bash "$HERE/$t"; then
    echo "--- $t OK"
  else
    echo "--- $t FAILED"
    status=1
  fi
  echo
done

if [[ "$status" -eq 0 ]]; then
  echo "ALL GUARDS PASSED ✅"
else
  echo "ONE OR MORE GUARDS FAILED ❌"
fi
exit "$status"
