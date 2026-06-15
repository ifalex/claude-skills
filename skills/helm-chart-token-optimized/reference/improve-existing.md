# Improve an Existing Chart

Raise an existing Helm chart to this skill's best practices. Read this whenever you
enter **Improve mode** (the target already has a `Chart.yaml`); `SKILL.md` only points here.

**Core change from Create mode: Improve is diagnosis-driven, not interview-driven.**
You run linters (or a static audit), turn the findings into a **single consolidated
proposal** with safe defaults already chosen, and apply on **one** decision. You do
**not** run the Step-0 essentials interview and you do **not** emit a list of
gap-filling questions. Derivable fixes are pre-decided; genuinely app-specific unknowns
get a **safe default plus a one-line "override if…"** note — never a blocking question.

## Two strategies — present both, user picks one

| | **A — Harden in place** (default) | **B — Refactor / re-scaffold** |
|---|---|---|
| What | Additive / in-place field edits that fit the existing layout | Regenerate a standardized chart from `reference/templates/` via `scaffold.sh`, carrying the existing settings over |
| Structure | **Preserved** (golden rule below) | Replaced with this skill's canonical structure |
| Determinism | Byte-stable, structure-preserving | Generation is deterministic given a fixed `answers.env`; the *extraction* step is model-driven (judgement) |
| Risk | Low | Custom values not mappable to an answer key (app env vars, annotations, sidecars, extra manifests) can be **dropped** unless re-applied — review the before→after |
| Use when | The chart is broadly sound and just needs hardening | The chart is messy/inconsistent and the user explicitly wants it standardized/rebuilt |

Default recommendation is **A**. Offer **B** in the same proposal; do B only if the
user picks it. For B, see *Strategy B procedure* below.

## Procedure

1. **Inventory (read-only).** Read `Chart.yaml`, `values.yaml`, every file under
   `templates/`, any `values.schema.json`, and any env overlays. Map naming, layout,
   and which best-practice features already exist. Note custom values (app env vars,
   annotations, sidecars, extra objects) — these matter for Strategy B. Write nothing yet.
2. **Diagnose — linter-first (no questions).**
   - Run `helm template <chart>/ > /tmp/rendered.yaml`, then `kube-score score` and
     `kube-linter lint` on the rendered manifests. Parse findings into the gap list.
   - If a linter isn't installed: offer `brew install kube-score kube-linter` but **do
     not block** — fall back to the static *Audit checklist* below.
3. **Decide each gap with a safe default (no gap-filling questions).** Use the
   *Derivable defaults* table. Everything derivable is pre-decided. App-specific unknowns
   get a working safe default and a one-line "override if…" — they are **not** questions.
4. **Single proposal (the one decision).** Present the *Proposal format* below: findings
   grouped by severity with the fix already chosen, the **A vs B** choice, and the
   custom-value note. Then:
   - **Interactive:** wait for **one** reply — `approve A` / `approve B` / "adjust these
     items". Do not ask anything else first.
   - **Non-interactive harness** (Copilot CLI, IntelliJ, or the user says they can't
     answer back-and-forth): **do not stall.** Apply **Strategy A with the safe
     defaults**, then report the before→after for review. List any item where a default
     was assumed and how to override it. Never block on an unanswered question.
5. **Apply.** Strategy A: edit existing files in place, matching surrounding indentation
   and style; copy any *new* template files verbatim from `reference/templates/`
   (CHARTNAME substituted), adapting names to the existing convention. Strategy B: follow
   *Strategy B procedure*.
6. **Quality gates + summary.** Run the same gates as Create mode (`helm lint`,
   `helm template`, kube-linter/kube-score) and report a clear **before → after**.

## Golden rule (Strategy A): preserve structure

You are improving, not rewriting. **Do NOT:** rename the chart/files/templates; move,
split, or merge templates; reorder or rename `values.yaml` keys; change the
release/object naming scheme or helper-template names; swap the chart's helper style.
**Do:** add missing fields in place, add missing files that fit the existing convention,
set safer values, add `# --` doc comments. If a real improvement *requires*
restructuring, that's exactly what **Strategy B** is for — offer it, don't force it.

## Derivable defaults (replaces the old "gap → question mapping")

None of these are questions. Apply the default; note it in the proposal as overridable.

| Gap | Default to apply | Override note (one line, not a blocking question) |
|-----|------------------|---------------------------------------------------|
| runAsNonRoot / runAsUser | `runAsNonRoot: true`, `runAsUser: 10001`, `runAsGroup`/`fsGroup: 10001` | confirm UID if the image needs a specific one |
| Dropped capabilities | `capabilities.drop: [ALL]` | — |
| allowPrivilegeEscalation | `false` | — |
| seccompProfile | `RuntimeDefault` | — |
| Resource requests + limits | overlay `resourcesPreset` (nano dev / small uat / explicit prod) | override sizing if the app has explicit needs |
| Probes | TCP-socket liveness+readiness on the container port | override with an HTTP path if the app exposes one (e.g. `/healthz`) |
| readOnlyRootFilesystem | `true` + `emptyDir` for `/tmp` | if the app writes elsewhere, add those mounts (or set `false`) |
| imagePullPolicy | `IfNotPresent` (base) | — |
| ServiceAccount | dedicated SA, `automountServiceAccountToken: false` | leave token on only if the app calls the K8s API |
| PodDisruptionBudget | on for uat/prod overlays, `minAvailable: 1` | — |
| NetworkPolicy | permissive allow-all baseline, present in every env | tighten or set off if not wanted |
| values.schema.json | generate from current values | — |
| Multi-env overlays | add `values-dev/uat/prod.yaml` (diffs only) | — |
| helm-docs `# --` comments | add to leaf keys | — |
| Pod anti-affinity | soft default for >1 replica | — |
| `.helmignore` / `NOTES.txt` | add both | — |
| Image tag `latest` | **recommend** pinning; keep current tag, flag loudly | provide a tag/digest to pin to |

Image `latest` is the one item you cannot safely auto-resolve (only the user knows the
intended version), so flag it as a recommendation — still **not** a blocking question.

## Audit checklist (static fallback when linters absent)

Detect each item from the inventory, classify the gap, then apply the *Derivable
defaults*. Severity guide: securityContext/root/caps/probes/resources = **Critical/High**;
schema/overlays/SA/PDB = **Medium**; docs/labels/anti-affinity/.helmignore = **Low**.
Compare each item against the corresponding `reference/templates/` file as the "good"
reference, adapting to the existing chart's names and helper style.

## Strategy B procedure (model-driven re-scaffold)

Chosen only when the user picks B. There is **no extraction script** — you do the mapping.

1. **Read** the existing `Chart.yaml` + `values.yaml` (small) and skim `templates/` to
   detect the workload kind and which features exist.
2. **Write `answers.env`** mapping the existing settings to the keys in
   `answers.example.env` (name, image repo/tag, port, workload, service type, and the
   feature toggles inferred from values — `ingress.enabled`, `autoscaling.enabled`,
   `persistence.enabled`, etc.).
3. **Run the scaffold** into a *new* directory (not over the original):
   `bash <skill-dir>/scaffold.sh --answers answers.env --out <tmp>`.
4. **Re-apply custom values** the scaffold can't know about: copy the original chart's
   app-specific `env`, `podAnnotations`, sidecars, extra objects, and bespoke values into
   the regenerated chart. This is the lossy step — be thorough.
5. **Diff old → new** and present it. Call out anything that changed semantically so the
   user can catch a dropped custom value before replacing the original.
6. Run the **quality gates** and report before→after.

## Proposal format (present before any Strategy-A/B edits)

```
## Chart audit: <chart-name>   (diagnosis: kube-score N CRITICAL / kube-linter M errors)

### Critical
- [x] Runs as root → add securityContext runAsNonRoot:true, runAsUser:10001  (applied default)
- [x] No dropped capabilities → capabilities.drop:[ALL]                       (applied default)
### High
- [x] No resource limits → overlay resourcesPreset (nano/small/explicit)      (override sizing if needed)
- [x] No probes → TCP liveness+readiness on port <p>                          (override with HTTP path if any)
### Medium
- [x] No values.schema.json → generate from current values                   (applied default)
- [x] No env overlays → add values-dev/uat/prod.yaml                          (applied default)
### Low
- [x] Undocumented values.yaml → add helm-docs # -- comments                  (applied default)
- [ ] image tag `latest` → recommend pinning                                  (provide a tag/digest)

Custom values detected (preserved in A; re-applied manually in B): env[LOG_LEVEL,...], podAnnotations{...}

**Choose a strategy:**
- A) Harden in place — preserves your structure (recommended)
- B) Refactor / re-scaffold from the standard templates — replaces structure; I re-apply
     your custom values and show a before→after (review for dropped values)

Reply: **approve A** · **approve B** · or name items to adjust.
(Non-interactive: I'll apply A with these defaults and show you the before→after.)
```

After applying, report a **before → after** summary and run the quality gates.
