# Further Proposals — helm-chart-token-optimized

Ideas surfaced during a token/quality review of the skill. **Nothing here is
implemented** — this is a backlog to discuss. Each item lists impact, effort,
and risk so we can pick what's worth doing.

Already shipped (for context): **#1** templates never enter context (scaffold
renders on disk, ~40K tokens/chart saved), **#3** lazy reference loading
(~5–9K/path), **#4** tiered interview confirmed once.

Legend — Risk: 🟢 none (behavior identical) · 🟡 low · 🔴 changes behavior, needs sign-off.

---

## A. Token efficiency

### A1. #2 as strict relocation (agreed approach, not yet applied) — 🟢
Move the Improve-mode 7-step procedure out of always-loaded `SKILL.md` into
`reference/improve-existing.md` (which Improve mode already loads). SKILL.md
keeps a 3-line trigger + pointer. Step 0 gate, Red Flags, Common Mistakes,
Interview UX Rules, and the full Question Groups summary stay **verbatim**.
- **Impact:** ~9 lines / ~450 tokens off *every* turn. Optional inventory
  tightening adds ~6 lines.
- **Honest scope:** modest (~10% of SKILL.md). The big wins were already banked
  by #1/#3/#4; this is a steady per-turn trim that compounds over long sessions.
- **Effort:** ~15 min. **Risk:** 🟢 none — content relocates to a branch-gated ref.

### A2. Tighten the frontmatter `description` — 🟡
The `description` (~120 words) is loaded for routing at **every session start**,
for every skill, whether or not this skill is invoked. Trimming to ~50 words
while keeping the trigger phrases ("create a Helm chart", "scaffold", "convert
to Helm", "token") reduces always-on cost across the whole skill catalog.
- **Impact:** small per-session, but it's the one part that costs even when the
  skill is never used.
- **Risk:** 🟡 must preserve trigger keywords or routing degrades — test that
  "create a helm chart" still selects it.

### A3. `scaffold.sh --plan` for the confirmation step — 🟡
The model currently composes the single plan-summary prose for the "confirm
once" gate. Add a `--plan` (or reuse `--dry-run`) mode that prints a compact,
deterministic plan (chart name, workload, enabled features, security defaults
applied). The model runs it and relays the output instead of authoring the
summary.
- **Impact:** moves summary generation out of the model; also makes the
  confirmation itself deterministic.
- **Risk:** 🟡 the summary wording becomes script-owned; keep it readable.

---

## B. Correctness & drift

### B1. De-duplicate the values skeleton in `values-and-schema.md` — 🟢
That reference embeds a near-complete `values.yaml` skeleton (17 `@section`s)
that parallels the canonical `reference/templates/values.yaml.tmpl` (15). Two
copies of the same structure **will drift**. Replace the embedded skeleton with:
"the canonical structure is `values.yaml.tmpl` — read that file"; keep only what
the doc uniquely owns (section *order* rules + helm-docs `# --` comment
conventions). Same for the `values.schema.json` skeleton vs the template.
- **Impact:** removes ~150 lines of duplicated reference, kills a real drift
  source, smaller load when that ref is needed.
- **Risk:** 🟢 the tmpl is already the source of truth used by the scaffold.

### B2. Single source of truth for defaults — 🟡
Defaults live in **three** places: `scaffold.sh` shell defaults,
`answers.example.env` example values, and `explanations.md` documented defaults.
They can silently disagree. Can't fully DRY in bash, but we can *guard* it:
- assert `answers.example.env` keys ⊆ the keys `scaffold.sh` recognises;
- assert the defaults quoted in `explanations.md` match `scaffold.sh`.
- **Risk:** 🟡 a guard test, not a refactor — low.

### B3. Schema ↔ values coverage — 🟡
`values.schema.json` (template) and `values.yaml.tmpl` are independent. A value
added to one may be missing/contradicted in the other. `helm lint` validates
values against the schema, so a fully-enabled chart run through lint catches
most of it — but only if the test exercises every toggle on.
- **Action:** extend the determinism test to also generate an *all-features-on*
  chart and `helm lint` it.

---

## C. Tests & guardrails (cheap quality wins)

### C1. Placeholder-parity test — 🟢
Today every `%%PLACEHOLDER%%` in `values.yaml.tmpl` has a matching `add` line in
`scaffold.sh` (verified clean). Nothing stops a future edit from breaking that —
the symptom is a literal `%%X%%` shipping in a user's `values.yaml`. Add a tiny
test (the exact `comm` check used in this review) to `tests/` so CI fails if the
two sets ever diverge.
- **Impact:** prevents the single most embarrassing scaffold bug.
- **Effort:** ~10 lines. **Risk:** 🟢.

### C2. Render every overlay in the determinism test — 🟡
`run-scaffold-determinism.sh` compares scaffold output but doesn't `helm
template` the dev/uat/prod overlays. Add a step that renders all three (and the
all-features chart from B3) so an overlay that breaks templating is caught
without a model.
- **Risk:** 🟡 requires `helm` on the test runner (already assumed by the gates).

### C3. Deployed-copy staleness guard — 🟡
The original token blow-up was partly a **stale deployed skill**
(`~/.claude/skills/...` lagged the repo). Add a `make sync` / check that diffs
the deployed copy against the repo, or document a one-liner. Prevents silent
drift between what's tested and what runs.
- **Risk:** 🟡 environment-specific (Claude Code vs Copilot install paths differ).

---

## D. Bigger / needs-decision

### D1. Collapse v1 + v2, or make v2 the default — 🔴
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

---

## Suggested order if we proceed
1. **A1** (agreed) + **C1** + **B1** — all 🟢, immediate, no behavior change.
2. **C2 / B3** — strengthen the test net.
3. **A2 / A3 / B2 / C3** — 🟡, each its own small change.
4. **D1** — only after v2 is validated in real use.
