# Changes — interview gate, improve mode, determinism harness

**Date:** 2026-06-09
**Scope:** `helm-chart-creator` skill — three related improvements driven by real-world testing on a lower-capability model (Copilot / GPT-5-mini class).
**Files:**
- `skills/helm-chart-creator/SKILL.md` (modified)
- `skills/helm-chart-creator/reference/improve-existing.md` (new)
- `skills/helm-chart-creator/tests/` (new: `compare-charts.sh`, `run-determinism.sh`, `scenario-a.prompt.txt`, `scenario-a.md`, `README.md`, `.gitignore`)
- `README.md` (modified — skill table, usage, repo layout)

---

## Motivation

Testing the skill on a weaker model surfaced two failures and one latent risk:

1. **It skipped the interview.** The model treated "interview the user" as optional, assumed defaults, and generated a chart the user never agreed to.
2. **It only did greenfield.** There was no way to point it at an existing chart and have it improve/harden that chart in place.
3. **Determinism was implied, not guaranteed or testable.** Nothing named the mechanism (verbatim template copying) or let us measure run-to-run drift.

---

## 1. Interview is now a blocking gate

**What changed (`SKILL.md`):**
- New **`Step 0 — Detect Mode, Then STOP and Interview (MANDATORY)`** section, placed before all generation logic. No `Write`/`Edit`/file-creating `Bash` is allowed until the user has answered at least the mode question and Group 1.
- Explicitly states the non-exceptions: "the request looked simple", "low effort budget", "the prompt gave me enough" are **not** reasons to skip asking.
- **Express ≠ ask nothing** — Express still asks Group 1 + ingress + persistence. The only skip is the user explicitly saying *"use defaults for the rest"*, and only after Group 1.
- New **Red Flags table** naming the exact rationalizations a weak model uses to bypass the interview.
- Reinforced in Overview (`Always interview first`) and a new **CRITICAL** row in Common Mistakes.

**Why:** Defaults are opt-in. A generated chart the user never reviewed is the failure mode this skill exists to prevent.

## 2. Improve-existing-chart mode

**What changed:**
- `description` frontmatter + When-to-Use now advertise improve/harden/audit; trigger is "target path already contains a `Chart.yaml`".
- New **`Mode: Improve Existing Chart`** section in `SKILL.md`: inventory (read-only) → audit → **preserve structure** → severity-grouped proposal report → ask only gap-filling questions → approval gate → apply in place → quality gates with before→after.
- New **`reference/improve-existing.md`**: a 20-item audit checklist (detection + severity + derivable-vs-needs-answer), gap→question mapping back to `explanations.md`, the proposal-report template, and the structure-preservation rules.

**Key constraint:** improvements are **additive or in-place field edits only** — no renaming files, moving/splitting templates, or reordering `values.yaml` keys. Anything requiring restructuring is listed as a proposal, never imposed.

## 3. Determinism — named and testable

**What changed (`SKILL.md`):**
- New **Determinism** principle in Overview: same answers → ≥95% identical chart, achieved by copying `reference/templates/` **verbatim** (only `CHARTNAME` + documented per-feature values substituted), never paraphrasing or regenerating template bodies.
- Reinforced in Generation Procedure step 3 and a new Common Mistakes row.

**New test harness (`tests/`), platform-neutral:**
- `compare-charts.sh` — diffs two generated chart dirs; reports file-set Jaccard + line-level similarity (LCS via plain `diff`, works on GNU **and** BSD/macOS — no GNU-only flags); exits 0 if overall ≥ threshold (default 95%).
- `run-determinism.sh` — runs the same front-loaded prompt N times through **any** agent CLI via a one-line contract (`--driver` reads prompt on stdin, runs non-interactively, writes chart under cwd), then compares. Driver examples for Claude Code, Copilot CLI, Gemini CLI, Codex.
- `scenario-a.prompt.txt` / `scenario-a.md` — a fixed answer set (front-loaded prompt + human-readable form).
- Generated output is written outside the repo (`$TMPDIR/helm-determinism-runs/`) and git-ignored.

**Two notions documented:** *intra-platform* determinism (same CLI twice → ≥95%, the real gate) vs *cross-platform* (Claude vs Copilot → expected lower; a portability signal, not pass/fail).

---

## Validation done

- `compare-charts.sh` smoke-tested: identical dirs → 100% PASS; mutated dirs → correct per-file similarity and FAIL.
- Caught and fixed a real portability bug: the original used GNU-only `diff --unchanged-line-format`, which BSD/macOS diff rejects (and an `|| true` was masking it as `0` common lines). Replaced with portable normal-format `diff`.
- `run-determinism.sh` plumbing smoke-tested with a deterministic fake driver across 3 runs.

## Not done / follow-ups

- No live end-to-end run of the skill through a real agent CLI yet (intra-platform ≥95% is asserted by design, not yet measured on a real run). First real use of `run-determinism.sh` will confirm.
- The interview-gate enforcement is a *behavioral* property; the determinism harness intentionally bypasses the interview (front-loaded prompt) to test output. A separate behavioral check (bare "create a chart" → must ask before writing) is documented but not automated.
