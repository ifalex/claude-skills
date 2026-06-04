# Code Review — helm-docs values-documentation feature

**Date:** 2026-06-05
**Reviewer:** Claude Code (`/review`)
**Scope:** net diff `fdb68eb..cf3b9fe` — adds helm-docs values documentation to the `helm-chart-creator` skill
**Files:** `skills/helm-chart-creator/SKILL.md`, `reference/helm-docs.md` (new), `reference/values-and-schema.md`

**Verdict:** Approved — no CRITICAL/HIGH issues. The items below are follow-ups to address later.

---

## To fix

### MEDIUM — Values skeleton has no `# --` annotations, so an agent could emit an undocumented chart
- **Where:** `reference/values-and-schema.md:18` (note) vs. the 200-line skeleton at lines 20–238.
- **Problem:** The skeleton an agent copies has zero `# --` comments; only the 3-line example at line 8 is annotated. An agent under pressure may paste the skeleton verbatim → `values.yaml` with no descriptions → README with an empty Description column, silently.
- **Fix options (pick one):**
  - [ ] Annotate **one full section** in the skeleton (e.g. the `image:` block) as a worked model.
  - [ ] Add a hard check to `SKILL.md` step 4: "before step 5, confirm every leaf you intend to document has a `# --` directly above it."

### LOW — Re-running helm-docs overwrites hand-edited README prose
- **Where:** `reference/helm-docs.md:76` (custom layout section).
- **Problem:** Without a `README.md.gotmpl`, helm-docs regenerates the entire `README.md` from its built-in template, clobbering any prose a user later adds. The doc mentions `.gotmpl` for custom layout but doesn't warn that plain-README hand edits are lost on regen.
- [ ] Add one sentence: hand edits to a plain `README.md` are overwritten on regeneration; use `README.md.gotmpl` to preserve custom prose.

### LOW — Minor skeleton duplication
- **Where:** `reference/values-and-schema.md:8` (annotated `image:` example) and line 42 (un-annotated `image:` in full skeleton).
- **Problem:** Harmless, but the un-annotated copy is the one in the full skeleton — reinforces the MEDIUM issue above.
- [ ] Resolve together with the MEDIUM fix (annotating the skeleton's `image:` block removes the duplication mismatch).

---

## Process note (not a blocker)

- **Test coverage gap:** The change was validated by running helm-docs v1.14.2 against a sample chart (reference-skill "retrieval + application" test — appropriate). The untested path is end-to-end: *does an agent following the skill actually produce an annotated `values.yaml` AND a populated README?* That's exactly where the MEDIUM issue would surface.
  - [ ] (Optional) Add a pressure scenario: dispatch a subagent to generate a chart via the skill, confirm the resulting `values.yaml` has `# --` annotations and the README Description column is populated.

## Out of scope (noted in passing)

- `deploy.sh` uses `rm -rf "$dest"` before copy. Not part of this diff; flag only if hardening the deploy path later.
