# Further Proposals — helm-chart-token-optimized

Ideas surfaced during a token/quality review of the skill. **A1–C3 are now
implemented**; only **D1** remains an open proposal (it changes both skills'
routing and was deferred until v2 is validated in real use).

Already shipped earlier (for context): **#1** templates never enter context
(scaffold renders on disk, ~40K tokens/chart saved), **#3** lazy reference
loading (~5–9K/path), **#4** tiered interview confirmed once.

Legend — Risk: 🟢 none (behavior identical) · 🟡 low · 🔴 changes behavior, needs sign-off.

---

## A. Token efficiency

### A1. #2 as strict relocation — ✅ done — 🟢
Moved the Improve-mode 7-step procedure out of always-loaded `SKILL.md` into
`reference/improve-existing.md` (which Improve mode already loads). `SKILL.md`
keeps a short trigger + pointer; Step 0 gate, Red Flags, Common Mistakes,
Interview UX Rules, and the full Question Groups summary stay verbatim. Trims
every turn; behavior identical because the content loads exactly when Improve
mode activates.

### A2. Tighten the frontmatter `description` — ✅ done — 🟡
Shortened the routing `description` (~120 → ~60 words) while keeping the trigger
phrases ("create a Helm chart", "scaffolding a chart", "convert … to Helm",
"token", "existing chart"). This is the one cost paid at **every** session start
whether or not the skill is used.

### A3. `scaffold.sh --plan` for the confirmation step — ✅ done — 🟡
Added `--plan`: prints a compact, deterministic plan (chart, image, workload,
enabled features, security defaults, output dir) and exits **without writing**.
The model runs it and relays the output for the "confirm once" gate instead of
authoring the summary prose. `SKILL.md` Generation Procedure updated to use it.

---

## B. Correctness & drift

### B1. De-duplicate the values skeleton in `values-and-schema.md` — ✅ done — 🟢
Replaced the embedded ~220-line `values.yaml` + schema skeletons (which
paralleled the canonical `values.yaml.tmpl` / `values.schema.json` and would
drift) with pointers to those templates. The doc now keeps only what it uniquely
owns: section **order**, helm-docs `# --` comment conventions, and schema
coverage rules.

### B2. Single source of truth for defaults — ✅ done — 🟡
`tests/check-defaults-parity.sh` asserts the keys in `answers.example.env` are
identical to the variables `scaffold.sh` recognises (both directions), so a
renamed key can't silently lose effect. (explanations.md prose defaults stay a
human review — parsing them would make the guard flaky; noted in the script.)

### B3. Schema ↔ values coverage — ✅ done — 🟡
`tests/lint-all-features.sh` + `tests/answers.all-features.env` scaffold a chart
with **every** toggle on, then run `helm lint` (validates values against
`values.schema.json`) and `helm template` each overlay. SKIPs cleanly without
helm. Verified: 0 lint failures, all overlays render.

---

## C. Tests & guardrails

### C1. Placeholder-parity test — ✅ done — 🟢
`tests/check-placeholder-parity.sh` asserts every `%%X%%` in `values.yaml.tmpl`
has a matching `add X` in `scaffold.sh` and vice versa — fails CI if they ever
diverge (the symptom would be a literal `%%X%%` in a user's values.yaml).

### C2. Render every overlay in the determinism test — ✅ done — 🟡
`run-scaffold-determinism.sh` now (when helm is present) `helm template`s the
base chart and each `values-{dev,uat,prod}.yaml` overlay, so an overlay that
breaks rendering is caught without a model. helm-gated SKIP keeps it CI-safe.

### C3. Deployed-copy staleness guard — ✅ done — 🟡
`tests/check-deployed-sync.sh` diffs the deployed skill copy
(`~/.claude/skills/…`, `~/.copilot/skills/…`, or `--deployed <dir>`) against this
repo and flags drift, recommending `./deploy.sh helm-chart-token-optimized`.
SKIPs when no deployed copy exists. Kept out of `run-all.sh` (environment-specific).

All four no-model guards are aggregated by `tests/run-all.sh`.

---

## D. Bigger / needs-decision

### D1. Collapse v1 + v2, or make v2 the default — ⏳ open — 🔴
`helm-chart-creator` (v1) and `helm-chart-token-optimized` (v2) both match
"create a helm chart". Two near-identical skills mean (a) double maintenance and
(b) **trigger ambiguity** — the router may pick the verbose v1, or carry both
descriptions in context. Options, in rough order of cleanliness:
- make v2 the canonical skill and reduce v1 to a thin "see token-optimized"
  stub (or archive it);
- merge into one skill where the scaffold path is the default and the verbose
  teaching path is just a reference branch.
- **Why deferred:** the user explicitly chose to keep v1 untouched. Revisit once
  v2 is proven on Copilot. **Risk:** 🔴 affects both skills' routing.
