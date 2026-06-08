# Interview Catalog & Explanations

Each entry: the question, the **default**, a **one-liner** (always show), and an **Explain** block (read aloud only when the user asks "what is X?", "explain", or "I don't know"). After explaining, re-offer the question with the default.

---

## Group 1 — App identity

### Q1.1 App name
**Ask:** "What's the app/chart name? (lowercase, hyphens — e.g. `payments-api`)"
**Default:** derive from the image repository or current directory name.
**One-liner:** Becomes the chart name and the prefix for every Kubernetes object.
**Explain:** Helm uses this as `.Chart.Name`. Resource names become `<release>-<chart>`. Must be DNS-safe: lowercase alphanumeric and `-`, ≤63 chars.

### Q1.2 Description
**Ask:** "One-line description of the app?"
**Default:** "A Helm chart for <app name>"
**One-liner:** Shows up in `helm search` and the chart's metadata.

### Q1.3 App version
**Ask:** "What version is the app? (e.g. `1.4.0`)"
**Default:** `0.1.0`
**One-liner:** Sets `appVersion` (the app's version). The chart's own `version` starts at `0.1.0` and you bump it when the chart changes.
**Explain:** Two versions exist. `appVersion` tracks the software you're deploying (often matches the image tag). `version` (chart version) tracks changes to the chart packaging itself and follows semver — bump it on every chart change so Helm/registries see a new release.

### Q1.4 Image
**Ask:** "Container image? Give registry [docker.io], repository (e.g. `myorg/payments-api`), and tag (e.g. `1.4.0`)."
**Default:** registry `docker.io`, pullPolicy `IfNotPresent`.
**One-liner:** Where Kubernetes pulls the container from.
**Explain:** `registry/repository:tag`. Prefer an immutable tag or a `digest` (sha256:…) over `latest` so deploys are reproducible. Private registries also need `imagePullSecrets` — I'll wire a value for that.

### Q1.5 Container port(s)
**Ask:** "What port does the app listen on inside the container? (e.g. `8080`) Protocol? [TCP]"
**Default:** `8080`, TCP.
**One-liner:** The port your process binds to; the Service maps to it.
**Explain:** This is the *container* port (what the app binds). The Service exposes a (possibly different) port that routes to it. You can have several (e.g. HTTP 8080 + metrics 9090).

### Q1.6 Workload type
**Ask:** "Workload type? [Deployment] — Deployment / StatefulSet / DaemonSet."
**Default:** `Deployment`.
**One-liner:** Deployment = stateless interchangeable pods; StatefulSet = stable identity + per-pod storage; DaemonSet = one pod per node.
**Explain:**
- **Deployment** — for stateless apps (APIs, web servers). Pods are fungible, scale freely, rolling updates. The default and right choice for most apps.
- **StatefulSet** — for databases/queues needing stable network identity (`pod-0`, `pod-1`) and their own persistent volume each. Ordered, slower rollouts.
- **DaemonSet** — runs exactly one pod on every node (or a node subset). For node-level agents: log shippers, metrics exporters, CNI.
If unsure: stateless app → Deployment.

---

## Group 2 — Networking

### Q2.1 Service type
**Ask:** "How is the app reached? [ClusterIP] — ClusterIP / NodePort / LoadBalancer."
**Default:** `ClusterIP`.
**One-liner:** ClusterIP = internal only; NodePort = a port on every node; LoadBalancer = cloud LB with external IP.
**Explain:**
- **ClusterIP** — reachable only inside the cluster. Combine with an Ingress to expose HTTP(S) externally. The normal choice.
- **NodePort** — opens a high port (30000–32767) on *every* node's IP. Crude external access, mostly for dev/bare-metal. No load balancing, ugly ports.
- **LoadBalancer** — provisions a cloud load balancer (AWS ELB, GCP LB) with a real external IP. One LB per service = costs money. Good for non-HTTP or when you don't run an ingress controller.
Most web apps: ClusterIP + Ingress.

### Q2.2 Ingress
**Ask:** "Expose this over HTTP(S) via Ingress? [no]. If yes: hostname (e.g. `api.example.com`), ingressClassName [nginx], TLS?"
**Default:** disabled.
**One-liner:** Ingress = HTTP router that maps a hostname/path to your Service, usually with TLS.
**Explain:** An Ingress lets one external entry point (the ingress controller, e.g. nginx-ingress) route `api.example.com/...` to your ClusterIP Service. Needs an ingress controller installed in the cluster. `ingressClassName` selects which controller. Paths support exact/prefix matching.

### Q2.3 TLS mode
**Ask (only if ingress enabled):** "TLS? [cert-manager] — cert-manager / self-signed / none."
**Default:** `cert-manager` if ingress enabled.
**One-liner:** cert-manager auto-issues Let's Encrypt certs; self-signed for dev; none = HTTP only.
**Explain:**
- **cert-manager** — adds annotations so the cert-manager controller auto-issues and renews a real certificate (Let's Encrypt). Requires cert-manager + a ClusterIssuer in the cluster.
- **self-signed** — the chart generates a self-signed cert. Browsers warn. Fine for internal/dev.
- **none** — plain HTTP. Only for behind-the-LB termination or local testing.

---

## Group 3 — Reliability

### Q3.1 Replica count
**Ask:** "How many replicas to start with? [1]"
**Default:** `1` (overridden per environment — prod defaults to 3).
**One-liner:** How many identical pods run. More = higher availability + throughput.
**Explain:** For real availability you want ≥2 so a node failure or rollout doesn't drop you to zero. If you enable HPA, this number is just the starting point — the autoscaler takes over.

### Q3.2 Update strategy
**Ask:** "Update strategy? [RollingUpdate] — RollingUpdate / Recreate."
**Default:** `RollingUpdate`.
**One-liner:** RollingUpdate = zero-downtime gradual swap; Recreate = kill all, then start new (brief downtime).
**Explain:** **RollingUpdate** spins up new pods and drains old ones gradually (controlled by maxSurge/maxUnavailable) — no downtime. **Recreate** terminates every old pod before creating new ones — causes downtime but avoids two versions running at once (needed when versions can't coexist, e.g. exclusive DB locks or incompatible schema).

### Q3.3 HPA (autoscaling)
**Ask:** "Autoscale on load (HPA)? [no]. If yes: min [2], max [5], target CPU% [80]."
**Default:** disabled (prod overlay can enable it).
**One-liner:** HPA adds/removes pods automatically based on CPU/memory usage.
**Explain:** The HorizontalPodAutoscaler watches CPU/memory and scales replicas between min and max to hit a target utilization (e.g. keep CPU ~80%). Requires the metrics-server in the cluster and **resource requests set** (this chart sets them). When enabled, the workload's `replicas` field is omitted so HPA fully owns the count.

### Q3.4 PDB (disruption budget)
**Ask:** "Protect against voluntary disruptions (PDB)? [no]. If yes: minAvailable [1]."
**Default:** disabled (prod overlay enables it).
**One-liner:** A PodDisruptionBudget stops node drains/upgrades from taking down too many pods at once.
**Explain:** During *voluntary* disruptions (node drain, cluster upgrade), a PodDisruptionBudget enforces e.g. "always keep ≥1 (or ≥50%) available". Prevents an admin draining a node from accidentally taking your whole app offline. Only meaningful with ≥2 replicas.

---

## Group 4 — Security & Config

### Q4.1 Run-as user
**Ask:** "Run as which UID? [1001] (non-root)."
**Default:** `1001`, `runAsNonRoot: true`.
**One-liner:** The Linux user inside the container. Non-root is required by most security policies.
**Explain:** Running as root in a container is a common finding for kube-score/kube-linter and PodSecurity standards. UID 1001 is Bitnami's convention. Your image must allow this user to read its files. If the app *must* bind a port <1024, prefer adding the `NET_BIND_SERVICE` capability over running as root — ask me.

### Q4.2 Read-only root filesystem
**Ask:** "Make the container filesystem read-only? [true] (recommended)."
**Default:** `true`.
**One-liner:** Blocks writes to the container's filesystem — strong hardening — but the app needs writable mounts for any paths it writes.
**Explain:** `readOnlyRootFilesystem: true` means the container can't write anywhere except volumes you mount. Big security win (stops tampering). But many apps write to `/tmp`, caches, or logs — I'll add `emptyDir` mounts for those. If the app writes to unpredictable paths and you can't enumerate them, we set this to `false` and note it as a follow-up.

### Q4.3 ServiceAccount
**Ask:** "Create a dedicated ServiceAccount? [yes]. Annotations? (e.g. AWS IAM role ARN, GCP Workload Identity)"
**Default:** create one, `automountServiceAccountToken: false`.
**One-liner:** The identity the pod uses to talk to the Kubernetes API and (via annotations) cloud IAM.
**Explain:** A dedicated ServiceAccount lets you scope RBAC narrowly and attach cloud identity (IRSA on EKS, Workload Identity on GKE) via annotations. We disable token automount by default — the app gets a token only if it actually calls the K8s API.

### Q4.4 Environment variables
**Ask:** "Any plain (non-secret) env vars? e.g. `LOG_LEVEL=info`. [none]"
**Default:** none.
**One-liner:** Plain config passed as env vars. Secrets go separately (next question).

### Q4.5 Secrets
**Ask:** "Secret values (DB passwords, API keys)? [none] — existingSecret name / auto-generate / none."
**Default:** none; if needed, prefer **existingSecret**.
**One-liner:** existingSecret = reference a Secret you manage out-of-band (best); auto-generate = chart creates one; none = no secrets.
**Explain:**
- **existingSecret** — you create/manage the Secret (via Vault, SealedSecrets, External Secrets, or `kubectl`) and the chart just references it by name. Keeps secrets out of values.yaml and git. **Recommended.**
- **auto-generate** — the chart creates a Secret, generating random passwords if you don't supply them. Convenient but the value lives in the release.
- **none** — app needs no secrets.

### Q4.6 ConfigMap files
**Ask:** "Config files to mount (e.g. `application.yaml`, `nginx.conf`)? [none]"
**Default:** none.
**One-liner:** Mounts config file content into the container as files via a ConfigMap.
**Explain:** A ConfigMap holds non-secret config (file contents or key/values) mounted into the pod. Changing it triggers a rollout because the chart adds a checksum annotation that changes with the content.

---

## Group 5 — Persistence & Observability

### Q5.1 Persistence
**Ask:** "Persistent storage? [StatefulSet: yes / Deployment: no]. If yes: size [8Gi], storageClass [cluster default], mountPath, accessMode [ReadWriteOnce]."
**Default:** on for StatefulSet, off for Deployment.
**One-liner:** A PersistentVolumeClaim gives the pod durable disk that survives restarts.
**Explain:** Without persistence, pod storage is ephemeral — gone on restart. A PVC requests durable storage from a StorageClass. **accessMode**: `ReadWriteOnce` (RWO) = one node at a time (most block storage, EBS/PD); `ReadWriteMany` (RWX) = many pods/nodes share (NFS/EFS). ⚠️ A Deployment with >1 replica + RWO volume breaks — the replicas can't share the disk. Use StatefulSet (one PVC per pod) or RWX storage.

### Q5.2 Metrics endpoint
**Ask:** "Does the app expose Prometheus metrics? [no]. If yes: path [/metrics], port."
**Default:** disabled.
**One-liner:** A scrapeable HTTP endpoint exposing app metrics in Prometheus format.
**Explain:** If your app serves `/metrics`, we expose that port on the Service so Prometheus can scrape it. If not, leave it off — you can also add a sidecar exporter later.

### Q5.3 ServiceMonitor
**Ask (only if metrics enabled):** "Create a Prometheus ServiceMonitor? [no] (needs Prometheus Operator)."
**Default:** disabled.
**One-liner:** Tells a Prometheus Operator to automatically scrape this Service.
**Explain:** A ServiceMonitor is a CRD from the Prometheus Operator (kube-prometheus-stack). It declaratively registers your Service for scraping — no manual Prometheus config. Only works if the Operator is installed; otherwise it's an inert object.

### Q5.4 NetworkPolicy
**Ask:** "Add a NetworkPolicy? [no] — restricts which pods can reach this one."
**Default:** disabled; when enabled, default to allowing DNS egress + same-namespace ingress.
**One-liner:** A firewall for pod-to-pod traffic. Default-deny, then allow what's needed.
**Explain:** Without a NetworkPolicy, any pod can talk to any pod. A NetworkPolicy restricts ingress/egress by pod/namespace labels. We generate a sane baseline (allow DNS, allow same-namespace) you can tighten. ⚠️ Only enforced if the cluster's CNI supports it (Calico, Cilium); on others it's silently ignored.

---

## Environment overlays (always generated)

`values.yaml` holds the **common base**. Three overlays hold only the **diffs**:

| Setting | dev (SIT) `values-dev.yaml` | uat `values-uat.yaml` | prod `values-prod.yaml` |
|---------|------------------------------|------------------------|--------------------------|
| replicaCount | 1 | 2 | 3 |
| resources | `resourcesPreset: nano` | `small` | explicit requests+limits |
| image.pullPolicy | `Always` | `IfNotPresent` | `IfNotPresent` |
| HPA | off | off | on (if chosen) |
| PDB | off | minAvailable 1 | minAvailable 2 (if chosen) |
| ingress.tls | self-signed/none | cert-manager (staging issuer) | cert-manager (prod issuer) |
| NetworkPolicy | off | on | on (if chosen) |
| log level (if env) | debug | info | info/warn |
| podAntiAffinity | off | soft | soft (or hard) |

Apply with: `helm upgrade --install <release> ./<chart> -f ./<chart>/values-prod.yaml -n <ns>`.
The common `values.yaml` is always loaded first; the `-f` overlay layers on top.
