# values.yaml Structure & Schema

## Section order (follow exactly — Bitnami convention)

Always emit sections in this order. Every leaf param gets a `## @param <path> <description>` comment on the line(s) above it (this is what Bitnami's `readme-generator` consumes and what makes values self-documenting).

```yaml
# Copyright / license header (optional)

## @section Global parameters
global:
  imageRegistry: ""
  imagePullSecrets: []
  storageClass: ""

## @section Common parameters
nameOverride: ""
fullnameOverride: ""
namespaceOverride: ""
clusterDomain: cluster.local
commonLabels: {}
commonAnnotations: {}
diagnosticMode:
  enabled: false
  command: ["sleep"]
  args: ["infinity"]

## @section <App> image parameters
image:
  registry: docker.io
  repository: <repo>
  tag: "<tag>"
  digest: ""
  pullPolicy: IfNotPresent
  pullSecrets: []

## @section <App> deployment/workload parameters
replicaCount: 1
revisionHistoryLimit: 10
updateStrategy:
  type: RollingUpdate
  rollingUpdate: {}
podLabels: {}
podAnnotations: {}
automountServiceAccountToken: false
hostAliases: []
command: []
args: []
extraEnvVars: []
extraEnvVarsCM: ""
extraEnvVarsSecret: ""
extraVolumes: []
extraVolumeMounts: []
initContainers: []
sidecars: []

## @section Scheduling
podAffinityPreset: ""
podAntiAffinityPreset: soft
nodeAffinityPreset:
  type: ""
  key: ""
  values: []
affinity: {}
nodeSelector: {}
tolerations: []
topologySpreadConstraints: []
priorityClassName: ""
schedulerName: ""
terminationGracePeriodSeconds: ""

## @section Security
podSecurityContext:
  enabled: true
  fsGroup: 1001
  fsGroupChangePolicy: Always
  supplementalGroups: []
  sysctls: []
containerSecurityContext:
  enabled: true
  seLinuxOptions: {}
  runAsUser: 1001
  runAsGroup: 1001
  runAsNonRoot: true
  privileged: false
  readOnlyRootFilesystem: true
  allowPrivilegeEscalation: false
  capabilities:
    drop: ["ALL"]
  seccompProfile:
    type: RuntimeDefault

## @section Container ports / resources / probes
containerPorts:
  http: 8080
resources:
  requests:
    cpu: 100m
    memory: 128Mi
    ephemeral-storage: 50Mi    # kube-score requires this; harmless on all clusters
  limits:
    cpu: 500m
    memory: 512Mi
    ephemeral-storage: 1Gi
resourcesPreset: "nano"   # used only when resources is {}; presets also include ephemeral-storage
livenessProbe:
  enabled: true
  initialDelaySeconds: 10
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1
readinessProbe:
  enabled: true
  initialDelaySeconds: 5
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 6
  successThreshold: 1
startupProbe:
  enabled: false
  initialDelaySeconds: 0
  periodSeconds: 10
  timeoutSeconds: 5
  failureThreshold: 30
  successThreshold: 1
customLivenessProbe: {}
customReadinessProbe: {}
customStartupProbe: {}
lifecycleHooks: {}

## @section Traffic exposure
service:
  type: ClusterIP
  ports:
    http: 80
  nodePorts:
    http: ""
  clusterIP: ""
  loadBalancerIP: ""
  loadBalancerSourceRanges: []
  externalTrafficPolicy: Cluster
  sessionAffinity: None
  annotations: {}
  extraPorts: []
ingress:
  enabled: false
  ingressClassName: ""
  hostname: <app>.local
  path: /
  pathType: ImplementationSpecific
  annotations: {}
  tls: false
  selfSigned: false
  extraHosts: []
  extraPaths: []
  extraTls: []
  secrets: []

## @section Persistence  (StatefulSet, or Deployment if explicitly enabled)
persistence:
  enabled: false
  storageClass: ""
  accessModes: ["ReadWriteOnce"]
  size: 8Gi
  annotations: {}
  mountPath: /data
  selector: {}

## @section RBAC / ServiceAccount
serviceAccount:
  create: true
  name: ""
  annotations: {}
  automountServiceAccountToken: false
rbac:
  create: false
  rules: []

## @section Autoscaling / Disruption
autoscaling:
  enabled: false
  minReplicas: 2
  maxReplicas: 5
  targetCPU: 80
  targetMemory: ""
pdb:
  create: false
  minAvailable: 1
  maxUnavailable: ""

## @section Network policy
networkPolicy:
  enabled: false
  allowExternal: true
  allowExternalEgress: true
  extraIngress: []
  extraEgress: []
  ingressNSMatchLabels: {}
  ingressNSPodMatchLabels: {}

## @section Metrics
metrics:
  enabled: false
  service:
    ports:
      metrics: 9090
  serviceMonitor:
    enabled: false
    namespace: ""
    interval: 30s
    scrapeTimeout: ""
    labels: {}
    selector: {}
    relabelings: []
    metricRelabelings: []
    honorLabels: false

## @section ConfigMap (app config)
configuration: ""           # inline file content, or
existingConfigmap: ""

## @section Extra deploy
extraDeploy: []
```

Adjust defaults to the user's answers. It's fine to keep disabled-feature sections in values.yaml as documented toggles (Bitnami does).

## values.schema.json

Generate a JSON Schema (draft-07) validating the high-value fields. Minimum coverage: `image`, `service`, `ingress`, `resources`, `replicaCount`, `persistence`, `autoscaling`. Keep it permissive (do not set `additionalProperties: false` at root — charts evolve). Base skeleton:

```json
{
  "$schema": "http://json-schema.org/draft-07/schema#",
  "title": "CHARTNAME values",
  "type": "object",
  "properties": {
    "replicaCount": { "type": "integer", "minimum": 0 },
    "image": {
      "type": "object",
      "properties": {
        "registry":   { "type": "string" },
        "repository": { "type": "string" },
        "tag":        { "type": "string" },
        "digest":     { "type": "string" },
        "pullPolicy": { "type": "string", "enum": ["Always", "IfNotPresent", "Never"] }
      },
      "required": ["repository"]
    },
    "service": {
      "type": "object",
      "properties": {
        "type": { "type": "string", "enum": ["ClusterIP", "NodePort", "LoadBalancer"] },
        "ports": { "type": "object" }
      }
    },
    "ingress": {
      "type": "object",
      "properties": {
        "enabled":  { "type": "boolean" },
        "hostname": { "type": "string" },
        "tls":      { "type": "boolean" }
      }
    },
    "resources": {
      "type": "object",
      "properties": {
        "requests": { "type": "object" },
        "limits":   { "type": "object" }
      }
    },
    "persistence": {
      "type": "object",
      "properties": {
        "enabled":     { "type": "boolean" },
        "size":        { "type": "string" },
        "storageClass":{ "type": "string" },
        "accessModes": { "type": "array", "items": { "type": "string", "enum": ["ReadWriteOnce", "ReadOnlyMany", "ReadWriteMany", "ReadWriteOncePod"] } }
      }
    },
    "autoscaling": {
      "type": "object",
      "properties": {
        "enabled":     { "type": "boolean" },
        "minReplicas": { "type": "integer", "minimum": 1 },
        "maxReplicas": { "type": "integer", "minimum": 1 },
        "targetCPU":   { "type": ["integer", "string"] }
      }
    }
  }
}
```
