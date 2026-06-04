---
name: helm-chart-creator
description: Use when creating a Helm chart for a Kubernetes application, scaffolding a new chart, converting an app/Deployment/Docker image to Helm, or generating production-grade chart templates with security hardening, multi-environment values (dev/uat/prod), values schema, and kube-linter/kube-score validation.
---

# Helm Chart Creator

## Overview

Generate a production-grade Helm chart by interviewing the user, applying Bitnami chart conventions, and validating the result with `kube-linter` and `kube-score`. The chart is **self-contained** — Bitnami `common` helpers are inlined into `_helpers.tpl`, with no OCI dependency.

**Core principle:** Never make the user feel stuck. Every question has a safe default and an on-demand explanation. A user who knows nothing about Kubernetes can complete the interview by accepting defaults; an expert can answer fast.

## When to Use

- "Create a Helm chart for my app"
- "Scaffold a chart for this Docker image / Deployment"
- "Convert this app to Helm"
- "I need a production-ready Helm chart with HPA / ingress / persistence"

When NOT to use: editing one value in an existing chart, or debugging a failed `helm install` (that's a templating/values problem, not scaffolding).

## Interview UX Rules (apply to EVERY question)

1. **State a default in brackets** and a **one-line example** of what the choice means.
   Example: `Service type? [ClusterIP] — ClusterIP = internal only; NodePort = port on every node; LoadBalancer = cloud external IP.`
2. The user may answer, say **"default"/"skip"**, or ask **"explain"/"what is X?"**.
3. If they ask to understand a concept, read `reference/explanations.md`, give the explanation **with when-to-use guidance and tradeoffs**, then re-offer the question.
4. The user may say **"use defaults for the rest"** at any point — stop asking, apply all remaining defaults, and list what you chose.
5. **Security-critical defaults are never silent.** When you apply hardening defaults (non-root, readOnlyRootFilesystem, dropped capabilities, resource limits, probes), state them explicitly in your summary so the user can override.
6. Ask in **groups** (below), not one giant wall. Confirm the group's answers before moving on.

## Choose a Mode First

Ask once, up front:

> **Guided or Express?**
> - **Guided** — I walk through each option and explain anything you don't recognize. Best if you're new to Helm/Kubernetes.
> - **Express** — I ask only the essentials (Group 1 + ingress + persistence) and apply safe production defaults for everything else, then show you the full list to tweak.

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

## Generation Procedure

After the interview:

1. **Confirm the plan** — list chart name, workload type, every enabled feature, and all security defaults applied. Get a yes before writing.
2. **Create the chart directory** at the path the user wants (default: `./<chart-name>/`). Never write to a repo root if other layout is conventional — ask if unsure.
3. **Write files** using `reference/templates/` as the source of truth. Replace the `CHARTNAME` placeholder with the real chart name everywhere. Only emit templates for enabled features (e.g. skip `hpa.yaml` if HPA disabled).
   - Required always: `Chart.yaml`, `values.yaml`, `values.schema.json`, `PARAMETERS.md`, `values-dev.yaml`, `values-uat.yaml`, `values-prod.yaml`, `templates/_helpers.tpl`, `templates/<workload>.yaml`, `templates/service.yaml`, `templates/serviceaccount.yaml`, `templates/NOTES.txt`, `templates/extra-list.yaml`, `.helmignore` (the reference file is named `dot-helmignore` — rename on copy)
   - Workload-specific: `<workload>` = `deployment.yaml` | `statefulset.yaml` | `daemonset.yaml` (emit exactly one). For StatefulSet also emit `headless-service.yaml`. For a **Deployment with persistence**, also emit `pvc.yaml` (StatefulSet uses its built-in `volumeClaimTemplates` instead — do NOT emit pvc.yaml for it).
   - Conditional: `ingress.yaml`, `configmap.yaml`, `secrets.yaml`, `hpa.yaml` (Deployment only), `pdb.yaml`, `networkpolicy.yaml`, `servicemonitor.yaml`
4. **Build values.yaml** following the Bitnami section order in `reference/values-and-schema.md`. Every param gets a `## @param <dotted.path> <description>` doc comment placed **directly above its leaf key** (the values-docs generator reads the default from the next line, so placement matters).
5. **Generate `PARAMETERS.md`** — a markdown table of every configurable value, its description, and default, built from the `## @param` metadata. Default to the dependency-free generator in `reference/values-docs.md`; if the user wants the canonical Bitnami tool (which can also regenerate `values.schema.json` from the same metadata), use `readme-generator-for-helm` per that file.
6. **Run quality gates** (next section). Fix until clean.
7. **Summarize**: tree of files created (including `PARAMETERS.md`), validation results, and the exact `helm install` / `helm upgrade` commands per environment.

## Quality Gates (MANDATORY — do not declare done until clean)

Full commands, install instructions, and the failure→fix table are in **`reference/quality-gates.md`**. Procedure:

1. `helm lint <chart>/` and `helm template <chart>/ -f <chart>/values-prod.yaml` must both succeed (catches template/syntax errors).
2. If `kube-linter` / `kube-score` are installed, run them on the rendered prod manifests. If not installed, offer to `brew install kube-linter kube-score` (or document it) and fall back to `helm lint` + a manual review against the fix table.
3. **Fix every CRITICAL/HIGH finding** by adjusting templates or values, then re-run. Verified baseline: the default chart passes **kube-linter with 0 errors**. **kube-score** is stricter and flags 4 things on defaults (ephemeral-storage, identical probes, UID<10000, pull policy) — `reference/quality-gates.md` lists the exact resolution for each and which are safe to suppress. Reach 0 CRITICAL before declaring done.
4. Report the final tool output verbatim. If a check was skipped (tool not installed), say so — don't imply it passed.

## Common Mistakes

| Mistake | Fix |
|---------|-----|
| Asking 22 questions in one message | Ask in groups; confirm each group |
| Silently picking security values | Always state hardening defaults applied |
| `readOnlyRootFilesystem: true` with no writable mount | Add an `emptyDir` for `/tmp` and any app write paths, or warn + set false |
| Emitting `hpa.yaml` AND hardcoded `replicas` | When HPA enabled, omit `replicas` from the Deployment (HPA owns it) |
| Forgetting `CHARTNAME` replacement | Search the generated chart for `CHARTNAME` before validating |
| Declaring done without running gates | Run `helm lint` + `helm template` minimum, every time |
| Persistence on a Deployment with >1 replica | Warn: RWO volumes don't share; use StatefulSet or RWX storage |
| `PARAMETERS.md` shows `{}` for a scalar value | The `## @param` was placed above a parent key, not its leaf — move it directly above the leaf and regenerate |
| Skipping `PARAMETERS.md` | Always generate it from `values.yaml` metadata so users have a values reference |

## Reference Files

- `reference/explanations.md` — full question catalog, defaults, "what is X" explanations, per-env overlay defaults
- `reference/values-and-schema.md` — values.yaml section order + values.schema.json structure
- `reference/values-docs.md` — generate `PARAMETERS.md` (values reference) from `## @param` metadata; dependency-free generator + optional Bitnami `readme-generator-for-helm`
- `reference/templates/` — every template file body (with `CHARTNAME` placeholder)
- `reference/quality-gates.md` — kube-linter + kube-score install, commands, failure→fix table
