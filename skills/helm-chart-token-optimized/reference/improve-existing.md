# Improve an Existing Chart

How to raise an existing Helm chart to this skill's best practices **without changing its structure**. Use this with the "Mode: Improve Existing Chart" procedure in `SKILL.md`.

## Golden rule: preserve structure

You are improving, not rewriting. **Do NOT:**

- Rename the chart, files, or templates.
- Move, split, or merge template files (e.g. don't break `deployment.yaml` into partials).
- Reorder or rename keys in `values.yaml`, or change the existing nesting.
- Change the release/object naming scheme or the helper-template names already in use.
- Swap the chart's helper style (e.g. force Bitnami `common.*` onto a chart that uses its own `_helpers.tpl`).

**Do:** add missing fields in place, add missing files that fit the existing convention, set safer values, and add `# --` doc comments. If a real improvement *requires* restructuring, record it as a **proposal** and let the user decide — never impose it.

## Audit checklist

For each item, determine the chart's current state from the inventory, then classify the gap. "Derivable" means you can fix it without asking; "needs answer" means ask the mapped question.

| # | Best practice | How to detect | Severity if missing | Derivable / needs answer |
|---|---------------|---------------|---------------------|--------------------------|
| 1 | **Non-root + `runAsNonRoot`** | `securityContext.runAsNonRoot: true`, `runAsUser` set (≥10000 preferred) | Critical | Derivable (default UID); confirm UID via Q4.1 if app-specific |
| 2 | **Dropped capabilities** | `containerSecurityContext.capabilities.drop: [ALL]` | Critical | Derivable |
| 3 | **`readOnlyRootFilesystem`** | set `true` + writable `emptyDir` for `/tmp` etc. | High | Needs answer (Q4.2 — which paths the app writes) |
| 4 | **`allowPrivilegeEscalation: false`** | container securityContext | High | Derivable |
| 5 | **Resource requests + limits** | `resources.requests/limits` (cpu, memory) | High | Derivable via overlay presets (`resourcesPreset` nano/small/explicit — see `explanations.md` § Environment overlays); confirm sizing only if the app has explicit needs |
| 6 | **Liveness / readiness probes** | `livenessProbe`, `readinessProbe` on the container | High | Port derivable from `containerPort` (Q1.5); health **path** has no preset question — ask directly |
| 7 | **Values schema** | `values.schema.json` present + covers top-level keys | Medium | Derivable from existing values |
| 8 | **Multi-env overlays** | `values-dev/uat/prod.yaml` present | Medium | Derivable (generate overlays with diffs only) |
| 9 | **helm-docs `# --` comments** | leaf keys in `values.yaml` documented | Low | Derivable |
| 10 | **ServiceAccount + token automount** | dedicated SA, `automountServiceAccountToken: false` | Medium | Needs answer if app calls K8s API (Q4.3) |
| 11 | **PodDisruptionBudget** | `pdb.yaml` / `PodDisruptionBudget` | Medium | Needs answer (Q3.4) |
| 12 | **HPA** | `hpa.yaml` / `HorizontalPodAutoscaler` | Low | Needs answer (Q3.3) |
| 13 | **NetworkPolicy** | `networkpolicy.yaml` | Low | Needs answer (Q5.4) |
| 14 | **Image tag immutability** | tag is not `latest`; digest preferred | Medium | Needs answer if `latest` (Q1.4) |
| 15 | **`imagePullPolicy`** | `IfNotPresent` (not `Always` in prod) | Low | Derivable |
| 16 | **Pod anti-affinity** | spread across nodes for >1 replica | Low | Derivable (soft default) |
| 17 | **`.helmignore`** | present | Low | Derivable |
| 18 | **NOTES.txt** | post-install usage notes | Low | Derivable |
| 19 | **Labels** | standard `app.kubernetes.io/*` labels | Low | Derivable |
| 20 | **Probes/limits parity across overlays** | prod has explicit limits | Low | Derivable |

Compare each item against the corresponding `reference/templates/` file as the "good" reference — but adapt to the existing chart's names and helper style.

## Gap → question mapping

Only ask for gaps that aren't derivable from the chart. Reuse the exact question text/defaults/explanations from `reference/explanations.md`:

| Gap | Question(s) |
|-----|-------------|
| readOnlyRootFilesystem writable paths | Q4.2 |
| resource sizing | overlay `resourcesPreset` (nano/small/explicit) — see `explanations.md` § Environment overlays; ask only if the app needs explicit cpu/memory values |
| probe health path | ask directly (no preset question); probe **port** = container port (Q1.5) |
| ServiceAccount / IAM annotations | Q4.3 |
| PDB minAvailable | Q3.4 |
| HPA min/max/target | Q3.3 |
| NetworkPolicy scope | Q5.4 |
| image tag/digest (if `latest`) | Q1.4 |
| ingress/TLS (only if user wants to add) | Q2.2 / Q2.3 |
| persistence (only if user wants to add) | Q5.1 |

Do not re-ask anything the existing chart already answers (e.g. don't ask the port if `containerPort` is set — confirm it instead).

## Proposal report format

Present before doing any edits. Group by severity, highest first:

```
## Chart audit: <chart-name>

### Critical (fix before production)
- [ ] **Runs as root** — no `runAsNonRoot`. Proposed: add pod securityContext
      `runAsNonRoot: true`, `runAsUser: 10001`. (auto-applicable)
- [ ] **No dropped capabilities** — Proposed: `capabilities.drop: [ALL]`. (auto-applicable)

### High
- [ ] **No resource limits** — Proposed: add requests/limits via overlay
      `resourcesPreset` (nano dev / small uat / explicit prod). (auto-applicable;
      override the size if the app needs explicit values)
- [ ] **No readiness/liveness probes** — Proposed: add probes on the container
      port. NEEDS ANSWER: health path? (port = containerPort)

### Medium
- [ ] No `values.schema.json` — Proposed: generate from current values. (auto-applicable)
- [ ] No env overlays — Proposed: add values-dev/uat/prod.yaml (diffs only). (auto-applicable)

### Low
- [ ] values.yaml undocumented — Proposed: add `# --` helm-docs comments. (auto-applicable)

**Structure preserved:** no files renamed/moved, no keys reordered.

Reply: approve all · approve auto-applicable only · pick items · and answer the NEEDS ANSWER questions below.
```

Wait for the user's decision and answers before editing — same blocking gate as Step 0. After applying, report a **before → after** summary and run the quality gates (`helm lint`, `helm template`, kube-linter/kube-score).
