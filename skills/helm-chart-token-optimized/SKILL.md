---
name: helm-chart-token-optimized
description: Token-lean, deterministic variant of helm-chart-creator. Use when creating a Helm chart for a Kubernetes application, scaffolding a new chart, or converting an app/Deployment/Docker image to Helm and you want minimal token usage with byte-identical repeatable output. Runs a short tiered interview, then generates the chart with a bundled scaffold.sh (templates never pass through the model's context). Produces production-grade templates with security hardening, multi-environment values (dev/uat/prod), values schema, and kube-linter/kube-score validation.
---

# Helm Chart Creator — token-optimized

## Overview

Generate a production-grade Helm chart by running a **short interview**, then handing the answers to a bundled **`scaffold.sh`** that copies templates and renders `values.yaml` **on disk**. The chart is **self-contained** — Bitnami `common` helpers are inlined into `_helpers.tpl`, with no OCI dependency.

This is the **token-optimized** sibling of `helm-chart-creator`. Three choices keep token use low *without* lowering output quality:

1. **The model never reads or writes template bodies.** `scaffold.sh` does the file production from a tiny `answers.env` the agent writes — removing ~40K tokens of read+write churn per chart versus copying ~20 templates through context.
2. **References load lazily** (see *Reference loading*): the verbose `explanations.md` loads only when a user asks to be taught; mode-specific files load only in their mode.
3. **The interview is tiered** (essentials first, full form on demand) and confirmed **once**, not per group — fewer turns, and each turn carries less context.

**Core principle:** Never make the user feel stuck. Every question has a safe default and an on-demand explanation. A user who knows nothing about Kubernetes can finish by accepting defaults; an expert can answer in one paste.

**Always interview first.** Defaults are *opt-in* — the user reaches them by answering, or by explicitly saying "use defaults for the rest." Generating a chart from assumed defaults without a single user reply is a failure of this skill (see Step 0). This is non-negotiable regardless of how simple the request looks or how low the model's effort budget is.

**Determinism.** Identical answers produce a **byte-identical** chart, because generation is a deterministic shell script (`cp` + `sed`), not model text generation. Template bodies are copied verbatim; `values.yaml` is rendered from `reference/templates/values.yaml.tmpl` by substituting placeholders. Repeated runs are 100% identical (the harness keeps a ≥95% threshold only to tolerate environment noise).

## Reference loading (load lazily — do NOT read everything up front)

To keep context small, read a reference file only when its branch is active:

| Read this | Only when |
|-----------|-----------|
| `reference/explanations.md` | the user chooses **Review the full list first**, or asks "explain / what is X?" — never on the Generate-now path |
| `reference/improve-existing.md` | you are in **Improve mode** (target already has a `Chart.yaml`) |
| `reference/values-and-schema.md` | you need to hand-edit values beyond what `scaffold.sh` renders, or in Improve mode |
| `reference/helm-docs.md` | generating the `README.md` values table |
| `reference/quality-gates.md` | a quality gate fails and you need the fix table |

On the common Create + Generate-now path you need **none** of these — the compact summaries in this file plus `scaffold.sh` are enough.

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

**In Create mode, your FIRST response must ask the essentials + offer the path — then WAIT for the reply.** Send ONE message containing both:

**(a) The essentials (Group 1 + the two most common toggles):**

> 1. **App name** (kebab-case) · **image** (registry/repository:tag) · **container port**
> 2. **Workload** [Deployment] — Deployment / StatefulSet / DaemonSet
> 3. **Ingress?** [no] · **Persistence?** [no]

**(b) How to finish — three ways, user picks one:**

> - **Generate now** — I apply safe production defaults for everything else (security hardening, probes, resources, multi-env values) and show you the full list to tweak afterward.
> - **Review the full list first** — I show all options (Groups 2–5) with defaults so you can adjust before I generate.
> - **Paste a filled answer file** — say "give me the answer file" and I hand you `answers.example.env` to fill in one shot (fastest; good for repeat/CI use).

**Hard rules for the gate:**
- Do NOT call `Write` / `Edit` / a file-creating `Bash` command (including `scaffold.sh`) until the user has answered at least the mode question and the Group 1 essentials.
- **"Generate now" ≠ ask nothing.** It still requires the essentials above to be answered first.
- If the opening request looks complete (e.g. "chart for nginx:1.25 on port 80"), you STILL send message (a)+(b): confirm identity, offer the path, then proceed. Never infer silently.
- After the user answers, do the **single confirmation** (one plan summary), then run `scaffold.sh`. Do not re-confirm group by group.

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
3. If they ask to understand a concept, **then** read `reference/explanations.md` (not before), give the explanation **with when-to-use guidance and tradeoffs**, then re-offer the question.
4. The user may say **"use defaults for the rest"** at any point — stop asking, apply all remaining defaults, and list what you chose.
5. **Security-critical defaults are never silent.** When you apply hardening defaults (non-root, readOnlyRootFilesystem, dropped capabilities, resource limits, probes), state them explicitly in your summary so the user can override.
6. **Confirm once, at the end** — collect all answers, then present a single plan summary for one yes before generating. Do NOT confirm group-by-group (that wastes turns/tokens).

## Question Groups

Compact summary below. Full question text, defaults, examples, and "what is X" explanations live in **`reference/explanations.md`** — read it **only** when a user asks to be taught or chooses *Review the full list first* (see *Reference loading*); the summary here is enough to drive the interview and fill `answers.env`.

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

## Generation Procedure (script-based — this is the token-saving core)

After the interview, **do not write template files by hand.** Run the bundled scaffold so template bodies never enter context:

1. **Confirm the plan once** — list chart name, workload type, every enabled feature, and the security defaults applied (non-root, readOnlyRootFilesystem, dropped caps, resource limits, probes). Get one yes.
2. **Write `answers.env`** — a small KEY=VALUE file mapping the interview answers to the keys in `answers.example.env`. Only this tiny file passes through context. Required: `CHART_NAME`, `IMAGE_REPOSITORY`, `IMAGE_TAG`; everything else has a safe default (omit a line to accept it). Map the toggles: `INGRESS_ENABLED`, `PERSISTENCE_ENABLED`, `HPA_ENABLED`, `PDB_ENABLED`, `NETWORKPOLICY_ENABLED`, `METRICS_ENABLED`, `SERVICEMONITOR_ENABLED`, `SECRETS_ENABLED`, `CONFIGMAP_ENABLED`.
3. **Run the scaffold:**
   ```bash
   bash <skill-dir>/scaffold.sh --answers answers.env --out <target-dir>
   ```
   It writes `<target-dir>/<chart-name>/` with: `Chart.yaml`, `values.yaml` (rendered, with helm-docs `# --` comments), `values.schema.json`, `values-{dev,uat,prod}.yaml`, `.helmignore`, the chosen workload template, `service`/`serviceaccount`/`NOTES`/`extra-list`/`_helpers`, plus only the conditional templates the toggles enabled. It validates inputs (kebab-case name, valid workload/service type) and substitutes `CHARTNAME` + all `%%...%%` placeholders. **Do not read the emitted template bodies** — trust the copy.
4. **Review only `values.yaml`** with the user if they want to tweak specifics (the rendered file is small and is the only place answer-specific values live). Edit values in place; never regenerate templates.
5. **Generate `README.md` with helm-docs** — `helm-docs --chart-search-root=./<chart>` writes the `## Values` table from the `# --` comments. If helm-docs isn't installed, offer `brew install norwoodj/tap/helm-docs` (or `go install`); if it can't be installed, **say the README was skipped — don't hand-fake the table**. (Avoid `-x` strict mode as a gate — see `reference/helm-docs.md`.)
6. **Run quality gates** (next section). Fix until clean.
7. **Summarize**: tree of files created (including `README.md`), validation results, and the exact `helm install` / `helm upgrade` commands per environment.

### Fallback (no shell access)

If the environment cannot run `scaffold.sh` (no Bash tool), fall back to manual copy: copy each needed body **verbatim** from `reference/templates/`, substitute `CHARTNAME`, render `values.yaml` from `reference/templates/values.yaml.tmpl` by replacing every `%%...%%` placeholder, and follow `reference/values-and-schema.md` for the section order. This costs the tokens the script was designed to avoid — prefer the script whenever shell is available.

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
| **Reading template bodies into context / hand-writing templates** | Run `scaffold.sh` — it copies templates on disk so they never burn tokens. Manual copy is the no-shell fallback only. |
| Confirming group-by-group | Ask essentials first (full list on demand), then confirm **once** before generating |
| Restructuring an existing chart in Improve mode | Preserve layout/naming; additive or in-place edits only |
| Silently picking security values | Always state hardening defaults applied |
| `readOnlyRootFilesystem: true` with no writable mount | Add an `emptyDir` for `/tmp` and any app write paths, or warn + set false |
| Emitting `hpa.yaml` AND hardcoded `replicas` | scaffold handles this; if hand-editing, omit `replicas` when HPA is enabled (HPA owns it) |
| Leftover `CHARTNAME` / `%%...%%` after a manual fallback | Search the generated chart for both before validating (the script never leaves them) |
| Declaring done without running gates | Run `helm lint` + `helm template` minimum, every time |
| Persistence on a Deployment with >1 replica | Warn: RWO volumes don't share; use StatefulSet or RWX storage |
| helm-docs table missing nested values | A `# --` on a parent key documents the whole block and hides its children — only comment leaves you want shown |
| Hand-writing the README values table | Generate it with `helm-docs` from `# --` comments; if helm-docs is unavailable, say it was skipped rather than faking it |

## Reference Files

- `scaffold.sh` — **the generator.** Reads `answers.env`, copies templates + renders `values.yaml` on disk. Run it instead of hand-writing files. `--help` for usage; `--dry-run` to preview the file list.
- `answers.example.env` — the answer-file template (hand this to a user for the paste-in-one-shot path; copy + fill to drive the scaffold).
- `reference/templates/values.yaml.tmpl` — the `values.yaml` source with `%%...%%` placeholders and helm-docs `# --` comments (rendered by the scaffold; used directly only in the no-shell fallback).
- `reference/templates/` — every template body (`CHARTNAME` placeholder) + `values.schema.json` + the env overlays.
- `reference/explanations.md` — full question catalog, defaults, "what is X" explanations, per-env overlay defaults. **Load only when teaching / Review-full-list.**
- `reference/improve-existing.md` — Improve-mode audit checklist, gap→question mapping, proposal-report format. **Load only in Improve mode.**
- `reference/values-and-schema.md` — values.yaml section order + schema structure (for hand-edits / fallback).
- `reference/helm-docs.md` — generate the chart `README.md` values table with helm-docs.
- `reference/quality-gates.md` — kube-linter + kube-score install, commands, failure→fix table.
- `tests/` — determinism harness; with the scaffold it runs **without any model call** (`run-determinism.sh` drives `scaffold.sh` directly) and expects 100% identical output.
