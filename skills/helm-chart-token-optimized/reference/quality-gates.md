# Quality Gates: kube-linter + kube-score

Run after generating the chart. Do not declare the chart done until `helm lint` and `helm template` pass, and (if installed) kube-linter/kube-score show no CRITICAL/HIGH findings.

## Step 0 — Tool detection

```bash
command -v helm        || echo "helm missing"
command -v kube-linter || echo "kube-linter missing"
command -v kube-score  || echo "kube-score missing"
```

If kube-linter / kube-score are missing, offer to install (macOS):
```bash
brew install kube-linter kube-score
```
Other platforms:
- kube-linter: https://docs.kubelinter.io/#/ (or `go install golang.stadmin... ` / GitHub releases `stackrox/kube-linter`)
- kube-score: https://github.com/zegl/kube-score/releases

If the user declines or they can't be installed, fall back to `helm lint` + `helm template` + a manual review against the fix table below. **Say explicitly that kube-linter/kube-score were skipped** — never imply they passed.

## Step 1 — Helm validation (always)

```bash
helm lint ./CHARTNAME
helm lint ./CHARTNAME -f ./CHARTNAME/values-dev.yaml
helm lint ./CHARTNAME -f ./CHARTNAME/values-prod.yaml

# Render must succeed for every environment (catches template + schema errors):
helm template rel ./CHARTNAME > /dev/null
helm template rel ./CHARTNAME -f ./CHARTNAME/values-dev.yaml  > /dev/null
helm template rel ./CHARTNAME -f ./CHARTNAME/values-uat.yaml  > /dev/null
helm template rel ./CHARTNAME -f ./CHARTNAME/values-prod.yaml > /dev/null
```

`values.schema.json` is enforced by `helm template`/`helm install` automatically — a schema violation fails the render.

## Step 2 — kube-linter (static analysis of templates)

```bash
kube-linter lint ./CHARTNAME
```
kube-linter understands Helm charts natively. It flags missing securityContext, missing resources, writable root filesystem, etc.

## Step 3 — kube-score (scores rendered manifests, per environment)

```bash
helm template rel ./CHARTNAME -f ./CHARTNAME/values-prod.yaml | kube-score score -
```
Run at least the prod overlay (strictest). kube-score grades each object; treat CRITICAL as must-fix and WARNING as should-fix.

## Step 4 — Fix loop

Adjust templates/values, re-run Steps 1–3 until clean.

**Reality check (verified):** the default chart passes `kube-linter` with **zero** errors. `kube-score`'s default checks are stricter than Bitnami's own conventions and flag **4 things** the base chart does not satisfy out of the box. Apply the prod hardening below to reach **0 CRITICAL**. Don't claim kube-score passed if you only ran kube-linter.

### The 4 kube-score CRITICALs on a default chart, and how to clear each

| kube-score finding | Why it fires | Resolution |
|--------------------|--------------|------------|
| **Container Ephemeral Storage Request and Limit** | no `ephemeral-storage` in resources | Already fixed: this skill's resources defaults + presets include `ephemeral-storage`. If you set a custom `resources:` block, add it there too. |
| **Pod Probes Identical** | liveness & readiness use the same TCP handler | Set `customReadinessProbe` to an HTTP check (e.g. `httpGet: { path: /ready, port: http }`). This both clears the check and is better practice. Only possible if the app has a readiness endpoint; if not, suppress with the annotation below. |
| **Container Security Context User Group ID** | kube-score wants UID/GID ≥ 10000; chart defaults to 1001 (Bitnami convention) | If your image supports it, set `containerSecurityContext.runAsUser/runAsGroup` and `podSecurityContext.fsGroup` to `10001`. **Do not** raise it blindly — the image's filesystem must be owned by/readable to that UID, or the container fails to start. If 1001 is required, suppress with the annotation below. |
| **Container Image Pull Policy** | tag-based image with `pullPolicy: IfNotPresent` | Pin the image by `digest` (recommended — immutable + reproducible) **and** set `image.pullPolicy: Always`, or accept and suppress. With a digest, `Always` adds no real pull cost. |

### Suppressing genuinely-opinionated checks

For checks you consciously accept (UID 1001 to match the image, TCP-only probes), add a `kube-score/ignore` annotation to the workload's pod template metadata rather than weakening security elsewhere:

```yaml
podAnnotations:
  kube-score/ignore: pod-probes,container-security-context-user-group-id
```

Never suppress: resource limits, dropped capabilities, readOnlyRootFilesystem, runAsNonRoot.

## Failure → Fix table

| Tool finding | Cause | Fix |
|--------------|-------|-----|
| `no-read-only-root-fs` (kube-linter) | `readOnlyRootFilesystem` not true | Keep `containerSecurityContext.readOnlyRootFilesystem: true`; add `emptyDir` for `/tmp` (template already does) |
| `run-as-non-root` / `Container has no configured security context` | securityContext missing/disabled | Ensure `containerSecurityContext.enabled: true`, `runAsNonRoot: true`, `runAsUser: 1001` |
| `Container has no configured memory/cpu limit` (kube-score) | resources empty | Set `resources.requests`+`.limits` (prod overlay does) or a non-`none` `resourcesPreset` |
| `Container has no configured liveness/readiness probe` | probes disabled | Keep `livenessProbe.enabled`/`readinessProbe.enabled: true`; set `customLivenessProbe` for HTTP if TCP isn't enough |
| `unset-cpu-requirements` / `unset-memory-requirements` (kube-linter) | same as above | same as above |
| `drop-net-raw-capability` / capabilities not dropped | `capabilities.drop` missing ALL | Keep `capabilities.drop: ["ALL"]` |
| `Pod NetworkPolicy` (kube-score) | no NetworkPolicy selects the pod | Enable `networkPolicy.enabled: true` (uat/prod overlays do) |
| `Deployment has pod/host antiAffinity` warning | single replica / no anti-affinity | Set `podAntiAffinityPreset: soft` and replicas ≥2 (uat/prod do) |
| `dangling-service` (kube-linter) | Service selector doesn't match pods | Selector uses `CHARTNAME.selectorLabels`; ensure pod template uses the same — don't edit one side only |
| `non-existent-service-account` | SA referenced but not created | Keep `serviceAccount.create: true` or set an existing `serviceAccount.name` |
| `helm template` error: `nil pointer` on `.Values.global...` | global block absent | Keep the `global:` section in values.yaml; helpers guard with `if .Values.global` |
| `minimum-three-replicas` (kube-linter, optional) | replicas <3 | Informational; prod overlay sets 3. Disable the check for dev if noisy |

## Optional: persist a config to silence non-prod noise

For dev overlays where single-replica/no-NetworkPolicy findings are expected, you can add a `.kube-linter.yaml` excluding `minimum-three-replicas` and `dangling-service` for that environment, but **never** exclude securityContext/resources/probe checks.
