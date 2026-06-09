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

**Reality check (verified):** the default chart passes `kube-linter` with **zero** errors, and the **uat and prod overlays score 0 kube-score CRITICAL out of the box** — no manual post-fixing. The **dev** overlay is intentionally permissive (single-replica SIT, NetworkPolicy off) and is *expected* to show one kube-score CRITICAL (Pod NetworkPolicy); that is by design, not a regression. Run kube-score against `values-prod.yaml` (and `values-uat.yaml`) — those are the deploy targets. Don't claim kube-score passed if you only ran kube-linter.

`tests/check-kube-quality.sh` enforces this (kube-linter clean + uat/prod 0 CRITICAL).

### How each kube-score CRITICAL is already handled

| kube-score finding | How the chart clears it by default |
|--------------------|------------------------------------|
| **Container Ephemeral Storage Request and Limit** | `ephemeral-storage` is in the resources defaults and every `resourcesPreset`. Add it if you write a custom `resources:` block. |
| **Container Security Context User Group ID** (UID/GID ≥ 10000) | Default `RUN_AS_USER=10001` → `runAsUser`/`runAsGroup`/`fsGroup` are all 10001. Override per image; some platforms (OpenShift) assign an even higher UID. |
| **Container Image Pull Policy** | The **uat and prod overlays set `image.pullPolicy: Always`**. dev keeps `Always` for fresh tags; the base default is `IfNotPresent`. Pinning by `digest` also clears it. |
| **Pod NetworkPolicy** | **uat and prod overlays enable `networkPolicy`**, and the template is always emitted so the overlay can turn it on. dev leaves it off by design. |
| **Deployment has PodDisruptionBudget** / replicas | uat/prod enable `pdb.create` and run ≥2 replicas; the PDB template is always emitted. A PDB defaults to `maxUnavailable: 1` (safe at any replica count — never blocks all evictions) unless you set `minAvailable`. |
| **Pod Probes Identical** | A generic chart only knows a TCP port, so liveness/readiness share one handler. The chart bakes a scoped `kube-score/ignore: pod-probes-identical` in `podAnnotations` with a comment. **Remove it and set distinct `customLivenessProbe`/`customReadinessProbe` httpGet checks** once you know the app's health endpoints — that's the proper fix. |

### Suppressing genuinely-opinionated checks

The only suppression the chart ships is `pod-probes-identical` (above), scoped via `podAnnotations`. If you consciously accept another opinionated check, add it the same way (object/pod annotation), e.g.:

```yaml
podAnnotations:
  kube-score/ignore: pod-probes-identical
```

Note the kube-score test ID is `pod-probes-identical` (not `pod-probes`). Never suppress: resource limits, dropped capabilities, readOnlyRootFilesystem, runAsNonRoot.

## Failure → Fix table

| Tool finding | Cause | Fix |
|--------------|-------|-----|
| `no-read-only-root-fs` (kube-linter) | `readOnlyRootFilesystem` not true | Keep `containerSecurityContext.readOnlyRootFilesystem: true`; add `emptyDir` for `/tmp` (template already does) |
| `run-as-non-root` / `Container has no configured security context` | securityContext missing/disabled | Ensure `containerSecurityContext.enabled: true`, `runAsNonRoot: true`, `runAsUser: 10001` (≥10000 satisfies kube-score) |
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
