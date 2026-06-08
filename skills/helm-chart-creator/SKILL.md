---
name: helm-chart-creator
description: Use when creating a Helm chart for a Kubernetes application, scaffolding a new chart, converting an app/Deployment/Docker image to Helm, or generating production-grade chart templates with security hardening, multi-environment values (dev/uat/prod), values schema, and kube-linter/kube-score validation. Also use to improve, harden, or audit an EXISTING Helm chart against these best practices without changing its structure.
---

# Helm Chart Creator

## Overview

Generate a production-grade Helm chart by interviewing the user, applying Bitnami chart conventions, and validating the result with `kube-linter` and `kube-score`. The chart is **self-contained** — Bitnami `common` helpers are inlined into `_helpers.tpl`, with no OCI dependency.

**Core principle:** Never make the user feel stuck. Every question has a safe default and an on-demand explanation. A user who knows nothing about Kubernetes can complete the interview by accepting defaults; an expert can answer fast.

**Always interview first.** Defaults are *opt-in* — the user reaches them by answering, or by explicitly saying "use defaults for the rest." Generating a chart from assumed defaults without a single user reply is a failure of this skill (see Step 0). This is non-negotiable regardless of how simple the request looks or how low the model's effort budget is.

**Determinism.** The same interview answers must produce the same chart. The mechanism: template bodies are **copied verbatim** from `reference/templates/` with only the `CHARTNAME` placeholder (and documented per-feature values) substituted — never paraphrased, reordered, or regenerated from memory. Repeated runs with identical input should be ≥95% identical.

## When to Use

- "Create a Helm chart for my app"
- "Scaffold a chart for this Docker image / Deployment"
- "Convert this app to Helm"
- "I need a production-ready Helm chart with HPA / ingress / persistence"
- "Improve / harden / audit my existing chart" → see **Mode: Improve Existing Chart**

When NOT to use: changing a single value in an existing chart, or debugging a failed `helm install` (that's a templating/values problem, not scaffolding or hardening).

## Step 0 — Detect Mode, Then STOP and Interview (MANDATORY)

**This is a blocking gate. Do NOT write, create, or edit any file until it is satisfied.** Generating a chart from assumed defaults — without one user reply — is a CRITICAL failure: it produces a chart the user never agreed to. The interview is not optional, and "the request looked simple" / "low effort budget" / "the prompt gave me enough" are not exceptions.

**First, detect the mode:**
- **Create mode** — no chart exists at the target path. Run the interview below.
- **Improve mode** — the target path (or a path the user names) already contains a `Chart.yaml`. Go to **Mode: Improve Existing Chart**; do NOT scaffold a fresh chart over an existing one.

**In Create mode, your FIRST response must ask — and then WAIT for the reply:**

> **Guided or Express?**
> - **Guided** — I walk through each option and explain anything you don't recognize. Best if you're new to Helm/Kubernetes.
> - **Express** — I ask only the essentials (Group 1 + ingress + persistence) and apply safe production defaults for the rest, then show you the full list to tweak.

Ask **Group 1 (App identity)** in that same first message.

**Hard rules for the gate:**
- Do NOT call `Write` / `Edit` / a file-creating `Bash` command until the user has answered at least the mode question and Group 1.
- **Express ≠ ask nothing.** Express still asks Group 1 + ingress + persistence.
- The only way to skip the remaining questions is the user explicitly saying **"use defaults for the rest"** — and only after Group 1 is answered.
- If the opening request looks complete (e.g. "chart for nginx:1.25 on port 80"), you STILL ask: confirm identity, offer the mode, then proceed. Never infer silently.

### Red Flags — STOP if you catch yourself thinking any of these

| Thought | Reality |
|---------|---------|
| "It's just a hello-world, defaults are fine" | Still ask. The user invoked an *interview* skill on purpose. |
| "The prompt already gave me enough to start" | A prompt is not interview answers. Ask the mode + Group 1. |
| "Asking is slow — I'll scaffold and let them edit" | Scaffolding before a reply violates the gate. Ask first. |
| "Low effort mode means skip the questions" | Effort budget never removes the interview gate. |
| "I'll pick safe defaults and just tell them after" | Security defaults are stated, not chosen silently. Ask, then confirm. |

## Interview UX Rules (apply to EVERY question)

1. **State a default in brackets** and a **one-line example** of what the choice means.
   Example: `Service type? [ClusterIP] — ClusterIP = internal only; NodePort = port on every node; LoadBalancer = cloud external IP.`
2. The user may answer, say **"default"/"skip"**, or ask **"explain"/"what is X?"**.
3. If they ask to understand a concept, read `reference/explanations.md`, give the explanation **with when-to-use guidance and tradeoffs**, then re-offer the question.
4. The user may say **"use defaults for the rest"** at any point — stop asking, apply all remaining defaults, and list what you chose.
5. **Security-critical defaults are never silent.** When you apply hardening defaults (non-root, readOnlyRootFilesystem, dropped capabilities, resource limits, probes), state them explicitly in your summary so the user can override.
6. Ask in **groups** (below), not one giant wall. Confirm the group's answers before moving on.

## Question Groups

Full question text, defaults, examples, and explanations live in **`reference/explanations.md`**. Read it before interviewing. Compact summary:

**Group 1 — App identity** (always asked)
- App name (kebab-case) · description · appVersion
- Image: registry [docker.io] / repository / tag
- Container port(s) + protocol [TCP]
- Workload type [Deployment] — Deployment / StatefulSet / DaemonSet

**Group 2 — Networking**
- Service type [ClusterIP]
- Ingress enabled? [no] → hostname, ingressClassName, TLS mode [cert-manager / self-signed / none]

**Group 3 — Reliability**
- replicaCount [1] · strategy [RollingUpdate]
- HPA enabled? [no] → minReplicas, maxReplicas, targetCPU% [80]
- PDB enabled? [no] → minAvailable [1]

**Group 4 — Security & Config**
- runAsUser [1001] · readOnlyRootFilesystem [true] (warn: needs writable `/tmp` via emptyDir if app writes files)
- ServiceAccount create? [true] + annotations (IAM role / Workload Identity)
- Env vars (plain) · Secrets [existingSecret name | auto-generate | none] · ConfigMap files? [none]

**Group 5 — Persistence & Observability**
- Persistence? [StatefulSet: yes 8Gi / Deployment: no] → size, storageClass, mountPath, accessMode [ReadWriteOnce]
- Metrics endpoint? [no] → path [/metrics], port
- ServiceMonitor? [no] (requires Prometheus Operator) · NetworkPolicy? [no]

**Group 6 — Environments** (always generated, no question needed)
- `values.yaml` (common base) + `values-dev.yaml` (SIT) + `values-uat.yaml` + `values-prod.yaml`. See `reference/explanations.md` § Environment overlays for the per-env defaults.

## Mode: Improve Existing Chart

Triggered when the target already contains a `Chart.yaml`. Goal: **raise an existing chart to these best practices without changing its structure.** Full audit checklist, gap→question mapping, and the proposal-report format live in **`reference/improve-existing.md`** — read it before starting. Procedure:

1. **Inventory (read-only).** Read `Chart.yaml`, `values.yaml`, every file under `templates/`, any `values.schema.json`, and any env overlays. Map the chart's naming scheme, layout, and which best-practice features it already has. Do not write anything yet.
2. **Audit** against the checklist in `reference/improve-existing.md` (security context, probes, resource requests/limits, values schema, multi-env overlays, helm-docs `# --` comments, PDB/HPA, NetworkPolicy, ServiceAccount token automount, image tag immutability, …). Classify each gap **Critical / High / Medium / Low**.
3. **Preserve structure (non-negotiable).** Do NOT rename files, move or split templates, reorder `values.yaml` keys, or change the release/helper naming scheme. Improvements must be **additive or in-place field edits** that fit the existing layout. If a best practice would require restructuring, list it as a *proposal* — never impose it.
4. **Proposal report.** Present gaps grouped by severity. For each: what's missing, why it matters, the exact proposed change, and whether it's **auto-applicable** (derivable from the chart) or **needs a user answer**.
5. **Ask only the gap-filling questions.** For gaps not derivable from the existing chart, ask the relevant question-group questions (reuse `reference/explanations.md`) — only the ones the chart doesn't already answer. **Same blocking gate as Step 0:** do not edit files until the user approves the proposal and answers the open questions (or explicitly says "apply the auto-fixable ones, skip the rest").
6. **Apply in place.** Edit the existing files to implement approved changes, matching the surrounding indentation and style. Copy any *new* template files verbatim from `reference/templates/` (CHARTNAME substituted), adapting names to the existing chart's convention.
7. **Quality gates + summary** — run the same gates as Create mode and report a clear **before → after** of what changed.

## Generation Procedure

After the interview:

1. **Confirm the plan** — list chart name, workload type, every enabled feature, and all security defaults applied. Get a yes before writing.
2. **Create the chart directory** at the path the user wants (default: `./<chart-name>/`). Never write to a repo root if other layout is conventional — ask if unsure.
3. **Write files** using `reference/templates/` as the source of truth. **Copy each template body verbatim** — substitute only the `CHARTNAME` placeholder (and documented per-feature values); do not paraphrase, reorder, or regenerate template content (this is what keeps repeated runs identical). Only emit templates for enabled features (e.g. skip `hpa.yaml` if HPA disabled).
   - Required always: `Chart.yaml`, `values.yaml`, `values.schema.json`, `values-dev.yaml`, `values-uat.yaml`, `values-prod.yaml`, `templates/_helpers.tpl`, `templates/<workload>.yaml`, `templates/service.yaml`, `templates/serviceaccount.yaml`, `templates/NOTES.txt`, `templates/extra-list.yaml`, `.helmignore` (the reference file is named `dot-helmignore` — rename on copy). `README.md` is generated in step 5 by helm-docs (not from a template).
   - Workload-specific: `<workload>` = `deployment.yaml` | `statefulset.yaml` | `daemonset.yaml` (emit exactly one). For StatefulSet also emit `headless-service.yaml`. For a **Deployment with persistence**, also emit `pvc.yaml` (StatefulSet uses its built-in `volumeClaimTemplates` instead — do NOT emit pvc.yaml for it).
   - Conditional: `ingress.yaml`, `configmap.yaml`, `secrets.yaml`, `hpa.yaml` (Deployment only), `pdb.yaml`, `networkpolicy.yaml`, `servicemonitor.yaml`
4. **Build values.yaml** following the section order in `reference/values-and-schema.md`. Document each value with a helm-docs **`# -- <description>`** comment placed **directly above its leaf key** (see `reference/helm-docs.md` for type hints, `# @default`, `# @ignored`, and the parent-key caveat).
5. **Generate `README.md` with helm-docs** — `helm-docs --chart-search-root=./<chart>` writes a chart README with the `## Values` table from the `# --` comments. If helm-docs isn't installed, offer `brew install norwoodj/tap/helm-docs` (or `go install`); if it can't be installed, **say the README was skipped — don't hand-fake the table**. (Avoid `-x` strict mode as a gate; it requires every nested key documented and will fail a normal chart — see `reference/helm-docs.md`.)
6. **Run quality gates** (next section). Fix until clean.
7. **Summarize**: tree of files created (including `README.md`), validation results, and the exact `helm install` / `helm upgrade` commands per environment.

## Quality Gates (MANDATORY — do not declare done until clean)

Full commands, install instructions, and the failure→fix table are in **`reference/quality-gates.md`**. Procedure:

1. `helm lint <chart>/` and `helm template <chart>/ -f <chart>/values-prod.yaml` must both succeed (catches template/syntax errors).
2. If `kube-linter` / `kube-score` are installed, run them on the rendered prod manifests. If not installed, offer to `brew install kube-linter kube-score` (or document it) and fall back to `helm lint` + a manual review against the fix table.
3. **Fix every CRITICAL/HIGH finding** by adjusting templates or values, then re-run. Verified baseline: the default chart passes **kube-linter with 0 errors**. **kube-score** is stricter and flags 4 things on defaults (ephemeral-storage, identical probes, UID<10000, pull policy) — `reference/quality-gates.md` lists the exact resolution for each and which are safe to suppress. Reach 0 CRITICAL before declaring done.
4. Report the final tool output verbatim. If a check was skipped (tool not installed), say so — don't imply it passed.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| **Generating a chart without asking anything** | **CRITICAL — always run the Step 0 interview. Defaults are opt-in, never silent.** |
| Rewriting template bodies from memory | Copy `reference/templates/` verbatim + substitute `CHARTNAME`; freeform rewrites break determinism |
| Restructuring an existing chart in Improve mode | Preserve layout/naming; additive or in-place edits only |
| Asking 22 questions in one message | Ask in groups; confirm each group |
| Silently picking security values | Always state hardening defaults applied |
| `readOnlyRootFilesystem: true` with no writable mount | Add an `emptyDir` for `/tmp` and any app write paths, or warn + set false |
| Emitting `hpa.yaml` AND hardcoded `replicas` | When HPA enabled, omit `replicas` from the Deployment (HPA owns it) |
| Forgetting `CHARTNAME` replacement | Search the generated chart for `CHARTNAME` before validating |
| Declaring done without running gates | Run `helm lint` + `helm template` minimum, every time |
| Persistence on a Deployment with >1 replica | Warn: RWO volumes don't share; use StatefulSet or RWX storage |
| helm-docs table missing nested values | A `# --` on a parent key documents the whole block and hides its children — only comment leaves you want shown |
| Hand-writing the README values table | Generate it with `helm-docs` from `# --` comments; if helm-docs is unavailable, say it was skipped rather than faking it |

## Reference Files

- `reference/explanations.md` — full question catalog, defaults, "what is X" explanations, per-env overlay defaults
- `reference/improve-existing.md` — Improve-mode audit checklist, gap→question mapping, proposal-report format, structure-preservation rules
- `reference/values-and-schema.md` — values.yaml section order (helm-docs `# --` annotations) + values.schema.json structure
- `reference/helm-docs.md` — generate the chart `README.md` values table with helm-docs; install, `# --` annotation syntax, and the `-x` documentation lint
- `reference/templates/` — every template file body (with `CHARTNAME` placeholder)
- `reference/quality-gates.md` — kube-linter + kube-score install, commands, failure→fix table
- `tests/` — platform-neutral determinism harness (`compare-charts.sh`, `run-determinism.sh`, fixed scenario); verifies same answers → ≥95% identical chart on any agent CLI
