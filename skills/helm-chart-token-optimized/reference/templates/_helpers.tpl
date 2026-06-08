{{/*
Standalone helpers — Bitnami-common conventions inlined (no library dependency).
Replace CHARTNAME with the chart name (e.g. payments-api) everywhere below.
*/}}

{{/* Chart name (respects nameOverride). */}}
{{- define "CHARTNAME.name" -}}
{{- default .Chart.Name .Values.nameOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/*
Fully qualified app name. Respects fullnameOverride; otherwise <release>-<chart>,
collapsing when the release name already contains the chart name.
Truncated to 63 chars (DNS label limit).
*/}}
{{- define "CHARTNAME.fullname" -}}
{{- if .Values.fullnameOverride -}}
{{- .Values.fullnameOverride | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- $name := default .Chart.Name .Values.nameOverride -}}
{{- if contains $name .Release.Name -}}
{{- .Release.Name | trunc 63 | trimSuffix "-" -}}
{{- else -}}
{{- printf "%s-%s" .Release.Name $name | trunc 63 | trimSuffix "-" -}}
{{- end -}}
{{- end -}}
{{- end -}}

{{/* Chart label "name-version". */}}
{{- define "CHARTNAME.chart" -}}
{{- printf "%s-%s" .Chart.Name .Chart.Version | replace "+" "_" | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Namespace (respects namespaceOverride). */}}
{{- define "CHARTNAME.namespace" -}}
{{- default .Release.Namespace .Values.namespaceOverride | trunc 63 | trimSuffix "-" -}}
{{- end -}}

{{/* Standard labels — recommended Kubernetes labels + commonLabels. */}}
{{- define "CHARTNAME.labels" -}}
helm.sh/chart: {{ include "CHARTNAME.chart" . }}
{{ include "CHARTNAME.selectorLabels" . }}
{{- if .Chart.AppVersion }}
app.kubernetes.io/version: {{ .Chart.AppVersion | quote }}
{{- end }}
app.kubernetes.io/managed-by: {{ .Release.Service }}
{{- with .Values.commonLabels }}
{{ toYaml . }}
{{- end }}
{{- end -}}

{{/* Selector labels — stable subset used in selectors (never change these). */}}
{{- define "CHARTNAME.selectorLabels" -}}
app.kubernetes.io/name: {{ include "CHARTNAME.name" . }}
app.kubernetes.io/instance: {{ .Release.Name }}
{{- end -}}

{{/* ServiceAccount name. */}}
{{- define "CHARTNAME.serviceAccountName" -}}
{{- if .Values.serviceAccount.create -}}
{{- default (include "CHARTNAME.fullname" .) .Values.serviceAccount.name -}}
{{- else -}}
{{- default "default" .Values.serviceAccount.name -}}
{{- end -}}
{{- end -}}

{{/*
Image reference. Honors global.imageRegistry override and image.digest
(digest wins over tag for reproducible pulls).
*/}}
{{- define "CHARTNAME.image" -}}
{{- $registry := .Values.image.registry -}}
{{- if .Values.global }}{{- if .Values.global.imageRegistry }}{{- $registry = .Values.global.imageRegistry -}}{{- end }}{{- end -}}
{{- $repo := .Values.image.repository -}}
{{- if .Values.image.digest -}}
{{- if $registry -}}{{- printf "%s/%s@%s" $registry $repo .Values.image.digest -}}{{- else -}}{{- printf "%s@%s" $repo .Values.image.digest -}}{{- end -}}
{{- else -}}
{{- $tag := .Values.image.tag | default .Chart.AppVersion -}}
{{- if $registry -}}{{- printf "%s/%s:%s" $registry $repo $tag -}}{{- else -}}{{- printf "%s:%s" $repo $tag -}}{{- end -}}
{{- end -}}
{{- end -}}

{{/* Render imagePullSecrets from image.pullSecrets + global.imagePullSecrets. */}}
{{- define "CHARTNAME.imagePullSecrets" -}}
{{- $secrets := list -}}
{{- if .Values.global }}{{- range .Values.global.imagePullSecrets }}{{- $secrets = append $secrets . -}}{{- end }}{{- end -}}
{{- range .Values.image.pullSecrets }}{{- $secrets = append $secrets . -}}{{- end -}}
{{- if $secrets }}
imagePullSecrets:
{{- range $secrets }}
  - name: {{ . }}
{{- end }}
{{- end -}}
{{- end -}}

{{/* Render a value that may itself contain template directives (for extraDeploy, etc.). */}}
{{- define "CHARTNAME.tplvalues.render" -}}
{{- if typeIs "string" .value -}}
{{- tpl .value .context -}}
{{- else -}}
{{- tpl (.value | toYaml) .context -}}
{{- end -}}
{{- end -}}

{{/* Probe timing fields, shared by liveness/readiness/startup probes. */}}
{{- define "CHARTNAME.probeTimings" -}}
initialDelaySeconds: {{ .initialDelaySeconds }}
periodSeconds: {{ .periodSeconds }}
timeoutSeconds: {{ .timeoutSeconds }}
failureThreshold: {{ .failureThreshold }}
successThreshold: {{ .successThreshold }}
{{- end -}}

{{/*
resources.preset — minimal CPU/memory presets, used only when .Values.resources is empty.
Mirrors Bitnami's common.resources.preset. Allowed: nano, micro, small, medium, large, xlarge, 2xlarge.
*/}}
{{- define "CHARTNAME.resources.preset" -}}
{{- $presets := dict
  "nano"    (dict "requests" (dict "cpu" "100m" "memory" "128Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "150m" "memory" "192Mi" "ephemeral-storage" "1Gi"))
  "micro"   (dict "requests" (dict "cpu" "250m" "memory" "256Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "375m" "memory" "384Mi" "ephemeral-storage" "1Gi"))
  "small"   (dict "requests" (dict "cpu" "500m" "memory" "512Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "750m" "memory" "768Mi" "ephemeral-storage" "2Gi"))
  "medium"  (dict "requests" (dict "cpu" "500m" "memory" "1024Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "1" "memory" "1536Mi" "ephemeral-storage" "2Gi"))
  "large"   (dict "requests" (dict "cpu" "1" "memory" "2048Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "2" "memory" "3072Mi" "ephemeral-storage" "2Gi"))
  "xlarge"  (dict "requests" (dict "cpu" "2" "memory" "4096Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "3" "memory" "6144Mi" "ephemeral-storage" "4Gi"))
  "2xlarge" (dict "requests" (dict "cpu" "4" "memory" "8192Mi" "ephemeral-storage" "50Mi") "limits" (dict "cpu" "6" "memory" "12288Mi" "ephemeral-storage" "4Gi"))
-}}
{{- if hasKey $presets . -}}
{{- toYaml (index $presets .) -}}
{{- else -}}
{{- printf "ERROR: unknown resourcesPreset %q" . | fail -}}
{{- end -}}
{{- end -}}
