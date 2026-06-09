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

**Reality check (verified):** the default chart passes `kube-linter` with **zero** errors, and **every environment — the base values plus dev/uat/prod — scores 0 kube-score CRITICAL out of the box**, no manual post-fixing. Security posture is identical across environments (NetworkPolicy present, `pullPolicy: Always`, non-root UID ≥10000); only **scale and resources** differ (dev 1 replica/nano, uat 2/small, prod 3 + explicit limits + HPA). dev keeps the NetworkPolicy permissive (allow-all) so it never blocks iteration while still satisfying the check. Run kube-score against any overlay — they all pass. Don't claim kube-score passed if you only ran kube-linter.

`tests/check-kube-quality.sh` enforces this (kube-linter clean + 0 CRITICAL on base/dev/uat/prod).

### How each kube-score CRITICAL is already handled

| kube-score finding | How the chart clears it by default |
|--------------------|------------------------------------|
| **Container Ephemeral Storage Request and Limit** | `ephemeral-storage` is in the resources defaults and every `resourcesPreset`. Add it if you write a custom `resources:` block. |
| **Container Security Context User Group ID** (UID/GID ≥ 10000) | Default `RUN_AS_USER=10001` → `runAsUser`/`runAsGroup`/`fsGroup` are all 10001. Override per image; some platforms (OpenShift) assign an even higher UID. |
| **Container Image Pull Policy** | Base default `image.pullPolicy: Always` (every environment). Use `IfNotPresent` only for images loaded locally onto kind/minikube; pinning by `digest` also clears the check. |
| **Pod NetworkPolicy** | `networkPolicy` is **on by default** (permissive allow-all baseline) in every environment; the template is always emitted. Tighten with `allowExternal: false` + `extraIngress`/`extraEgress`. |
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
