# helm-chart-token-optimized — determinism tests

Verifies the skill produces the **same chart from the same answers**. Because v2
generates via `scaffold.sh` (deterministic `cp`+`sed`), the primary test needs
**no agent/LLM at all** and expects **100%** identical output.

## Run everything (no model)

```bash
./run-all.sh
```

Runs the four no-model guards below in sequence and fails if any fails. The
helm-gated ones SKIP cleanly when `helm` is absent, so it's safe in minimal CI.

## Primary: zero-token scaffold determinism (no model)

```bash
./run-scaffold-determinism.sh                 # orders-api from answers.example.env
./run-scaffold-determinism.sh --answers my.env --chart-name my-app
```

Runs `scaffold.sh` twice and compares. This is the real determinism guarantee of
v2 — a non-100% result is a genuine bug in `scaffold.sh` or a template. Fast,
free, runs in CI. When `helm` is present it also `helm template`s the base chart
and each `values-{dev,uat,prod}.yaml` overlay to catch an overlay that breaks
rendering.

## Guards (no model, fast, CI-friendly)

| Script | Checks | Needs helm? |
|--------|--------|-------------|
| `check-placeholder-parity.sh` | every `%%X%%` in `values.yaml.tmpl` has a matching `add X` in `scaffold.sh` (and no dead `add` lines) — stops a literal `%%X%%` shipping in a user's values | no |
| `check-defaults-parity.sh` | `answers.example.env` keys are identical to the variables `scaffold.sh` recognises — stops a renamed key silently losing effect | no |
| `lint-all-features.sh` | scaffolds with **every** toggle on, then `helm lint` (values vs `values.schema.json`) + `helm template` each overlay — schema↔values coverage | yes (SKIPs without) |
| `check-kube-quality.sh` | scaffolds a default chart, asserts **kube-linter clean** + **kube-score 0 CRITICAL** on every environment (base + dev/uat/prod) | yes (SKIPs without) |
| `check-deployed-sync.sh` | diffs the **deployed** skill copy (`~/.claude/skills/…`, `~/.copilot/skills/…`) against this repo — warns when the live skill lags the source of truth | no |

`check-deployed-sync.sh` is environment-specific (it inspects your local install
paths) so it's **not** part of `run-all.sh`. Run it after editing the skill:

```bash
./check-deployed-sync.sh              # FAIL on drift (exit 1)
./check-deployed-sync.sh --warn-only  # report drift but exit 0
# in sync again after:  ../../deploy.sh helm-chart-token-optimized
```

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
- `run-all.sh` — run all four no-model guards; non-zero if any fails.
- `run-scaffold-determinism.sh` — scaffold twice, byte-compare (+ render overlays when helm present).
- `check-placeholder-parity.sh` — `%%X%%` ↔ `add X` parity (no model).
- `check-defaults-parity.sh` — `answers.example.env` keys ↔ `scaffold.sh` vars (no model).
- `lint-all-features.sh` — all toggles on; `helm lint` vs schema + render overlays.
- `check-kube-quality.sh` — kube-linter clean + kube-score 0 CRITICAL on every env.
- `check-deployed-sync.sh` — deployed skill copy vs repo (drift guard).
- `answers.all-features.env` — fixture enabling every toggle (drives `lint-all-features.sh`).
- `compare-charts.sh` — compare two chart dirs; exit 0 if overall ≥ threshold (95%).
- `run-determinism.sh` — run the same prompt N times via your CLI, then compare.
- `check-interview-gate.sh` — behavioral test: a no-answers prompt must make the
  skill ask first and write nothing (Step 0 gate). Uses a model.
- `gate-bare.prompt.txt` — a "looks complete" prompt with no answers (drives the
  gate test).
- `scenario-gate.md` — RED/GREEN baseline expectations for the interview gate.
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
> check — automated by `check-interview-gate.sh` (below).

## Behavioral: Step 0 interview gate (uses a model)

`run-determinism.sh` front-loads every answer to measure *output*. This is its
complement: it sends a prompt with **no answers** and asserts the skill **holds
the gate** — asks first, writes nothing.

```bash
# Baseline on the realistic target tier (Sonnet), NOT a weak model:
./check-interview-gate.sh --driver 'claude -p --model sonnet --permission-mode acceptEdits'
```

It runs the agent once in a fresh empty dir on `gate-bare.prompt.txt` (a request
that *looks* complete — `nginx:1.25` on port 80 — the exact "the prompt already
gave me enough" rationalization Step 0 targets) and PASSES only when **both**
hold: zero chart files written **and** the agent emitted interview questions. A
written `Chart.yaml`/`values.yaml` = gate breached = FAIL.

**Why Sonnet, not Haiku:** a weak model failing the gate is a capability signal,
not a skill defect; tuning the skill to force a weak model into compliance bloats
the always-loaded body and fights the token-optimized goal. Baseline compliance
on the tier users actually run; treat weaker models as a separate smoke check.

**RED baseline (skill-creator methodology):** to confirm the gate does real work,
run the same prompt through an agent that does **not** have the skill loaded (drop
the `Use the helm-chart-token-optimized skill.` line). Expected RED: it scaffolds
a chart from assumed defaults, writing files immediately. GREEN (skill present):
it asks first. See `scenario-gate.md`.
