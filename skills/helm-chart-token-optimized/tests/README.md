# helm-chart-token-optimized — determinism tests

Verifies the skill produces the **same chart from the same answers**. Because v2
generates via `scaffold.sh` (deterministic `cp`+`sed`), the primary test needs
**no agent/LLM at all** and expects **100%** identical output.

## Primary: zero-token scaffold determinism (no model)

```bash
./run-scaffold-determinism.sh                 # orders-api from answers.example.env
./run-scaffold-determinism.sh --answers my.env --chart-name my-app
```

Runs `scaffold.sh` twice and compares. This is the real determinism guarantee of
v2 — a non-100% result is a genuine bug in `scaffold.sh` or a template. Fast,
free, runs in CI.

## Secondary: end-to-end agent determinism (optional, uses a model)

The scripts below drive a full agent run (interview → `answers.env` → scaffold) to
confirm the *skill instructions* produce the scaffold call consistently — on **any**
agent harness (Claude Code, GitHub Copilot CLI, Gemini CLI, Codex). Generated chart
output is written outside the repo (see `.gitignore`).

## Why it's platform-neutral

The two pieces are deliberately harness-agnostic:

- **`compare-charts.sh`** — pure bash (works on GNU *and* BSD/macOS — no GNU-only
  flags). Takes two directories and reports file-set Jaccard + line-level
  similarity (LCS via plain `diff`). It does not know or care which agent
  generated the charts.
- **`run-determinism.sh`** — drives any CLI through a one-line **contract**:
  your `--driver` reads the prompt on **stdin**, runs **non-interactively**, and
  writes the chart **under the current working directory**. The runner supplies
  the plumbing; you supply the platform's invocation.

So the only platform-specific thing is *how you invoke your agent* — captured in
a single `--driver` string.

## Files
- `compare-charts.sh` — compare two chart dirs; exit 0 if overall ≥ threshold (95%).
- `run-determinism.sh` — run the same prompt N times via your CLI, then compare.
- `scenario-a.prompt.txt` — front-loaded prompt with ALL answers inline (a
  non-interactive run never stalls waiting for the interview).
- `scenario-a.md` — the same scenario as human-readable interactive answers.

## Quick start (any platform)

Run from this `tests/` directory (the scripts resolve their own paths, so you can
call them from anywhere):

```bash
# Pick the driver for YOUR harness (verify flags against your CLI version):
#   Claude Code : 'claude -p --permission-mode acceptEdits'
#   Copilot CLI : 'copilot -p --allow-all-tools'
#   Gemini CLI  : 'gemini -y'
#   Codex       : 'codex exec --full-auto -'
# Each must read the prompt on stdin. If yours takes the prompt as an argument:
#   'sh -c '\''copilot -p "$(cat)"'\'''

./run-determinism.sh --driver 'copilot -p --allow-all-tools' --runs 2 --threshold 95
```

That runs the skill twice (charts written under `$TMPDIR/helm-determinism-runs/`
by default; override with `--outroot`) and prints PASS/FAIL.

## Manual flow (no scriptable CLI — works literally anywhere)

1. Fresh session, paste `scenario-a.prompt.txt`, output to some `run1/` dir.
2. Fresh session, same prompt, output to `run2/`.
3. Compare:
   ```bash
   ./compare-charts.sh /path/to/run1/orders-api /path/to/run2/orders-api
   ```

The comparison step is identical regardless of platform.

## Two kinds of determinism

| Test | How | Expectation |
|------|-----|-------------|
| **Intra-platform** | run1 & run2 on the *same* CLI/model (`run-determinism.sh`) | **≥95%** — the skill's determinism guarantee |
| **Cross-platform** | run1 on Claude, run2 on Copilot/Gemini, then `compare-charts.sh` on the two dirs | **lower** — different models read the same skill differently; a portability signal, not a pass/fail gate |

For cross-platform: generate each chart on its own harness, then call
`compare-charts.sh dirX dirY` directly (skip the runner).

## Interpreting results
- **OVERALL ≥ 95% → PASS.** Acceptable determinism.
- **Template files differ → real bug.** Templates are copied verbatim by the
  skill, so any diff under `templates/*` means it regenerated instead of copying.
  Fix the skill (reinforce "copy verbatim"), don't lower the threshold.
- **Only values.yaml / README differ slightly** → usually cosmetic (comment
  wording); confirm it isn't a semantic value change.

> The front-loaded prompt intentionally bypasses the interview to test *output*
> determinism. The interview-enforcement (Step 0 gate) is a separate behavioral
> check — verify it by running the skill with a bare "create a chart" and
> confirming it asks before writing anything.
