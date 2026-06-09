#!/usr/bin/env bash
# scaffold.sh — deterministic Helm chart generator for helm-chart-token-optimized.
#
# WHY THIS EXISTS: it keeps template bodies OUT of the model's context window.
# Instead of the agent reading ~20 template files and writing them back out
# (~40K tokens round-trip per chart), the agent writes one small answers file
# and runs this script. The script copies templates and renders values.yaml on
# DISK. The agent never sees a template body. Output is byte-deterministic for
# identical answers.
#
# Usage:
#   ./scaffold.sh --answers answers.env --out ./           # writes ./<chart-name>/
#   ./scaffold.sh --answers answers.env --out /tmp/x --dry-run
#   ./scaffold.sh --answers answers.env --plan             # print plan summary, write nothing
#
# --plan prints a compact, deterministic confirmation summary (chart, workload,
# enabled features, security defaults) and exits WITHOUT writing files — use it
# for the "confirm once" gate so the summary is script-owned, not model-authored.
#
# The answers file is KEY=VALUE shell assignments (see answers.example.env).
# Required keys are validated; everything else has a safe production default.
#
# Portable to bash 3.2 / BSD sed (macOS) — no associative arrays, no GNU-only flags.

set -uo pipefail

HERE="$(cd "$(dirname "$0")" && pwd)"
TPL="$HERE/reference/templates"
ANSWERS=""
OUT="."
DRYRUN=0
PLAN=0

while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers)   ANSWERS="$2"; shift 2;;
    --out)       OUT="$2"; shift 2;;
    --templates) TPL="$2"; shift 2;;
    --dry-run)   DRYRUN=1; shift;;
    --plan)      PLAN=1; shift;;
    -h|--help)   sed -n '2,34p' "$0"; exit 0;;
    *) echo "scaffold: unknown arg: $1" >&2; exit 2;;
  esac
done

[[ -n "$ANSWERS" ]] || { echo "ERROR: --answers <file> is required" >&2; exit 2; }
[[ -f "$ANSWERS" ]] || { echo "ERROR: answers file not found: $ANSWERS" >&2; exit 2; }
[[ -d "$TPL" ]]     || { echo "ERROR: templates dir not found: $TPL" >&2; exit 2; }

# --- Defaults (overridden by the answers file) -------------------------------
CHART_NAME=""; DESCRIPTION=""; APP_VERSION=""
IMAGE_REGISTRY="docker.io"; IMAGE_REPOSITORY=""; IMAGE_TAG=""
CONTAINER_PORT="8080"; WORKLOAD="Deployment"
SERVICE_TYPE="ClusterIP"; SERVICE_PORT="80"
REPLICA_COUNT="1"; RUN_AS_USER="10001"; READ_ONLY_ROOT_FS="true"
MAINTAINER="team"
INGRESS_ENABLED="false"; INGRESS_HOSTNAME=""; INGRESS_CLASS=""; INGRESS_TLS="none"
PERSISTENCE_ENABLED="false"; PERSISTENCE_SIZE="8Gi"; PERSISTENCE_MOUNT="/data"
HPA_ENABLED="false"; HPA_MIN="2"; HPA_MAX="5"; HPA_TARGET_CPU="80"
# Empty PDB_MIN_AVAILABLE => the PDB renders maxUnavailable:1 (safe at ANY replica
# count; never blocks all evictions). Overlays/answers can set minAvailable explicitly.
PDB_ENABLED="false"; PDB_MIN_AVAILABLE=""
# NetworkPolicy on by default = permissive allow-all baseline (present in every
# environment so kube-score passes; tighten via allowExternal:false + extra rules).
NETWORKPOLICY_ENABLED="true"
METRICS_ENABLED="false"; SERVICEMONITOR_ENABLED="false"; METRICS_PORT="9090"
SA_CREATE="true"
SECRETS_ENABLED="false"; CONFIGMAP_ENABLED="false"

# shellcheck disable=SC1090
. "$ANSWERS"

# --- Validate ----------------------------------------------------------------
fail=0
for req in CHART_NAME IMAGE_REPOSITORY IMAGE_TAG; do
  if [[ -z "${!req}" ]]; then echo "ERROR: required answer missing: $req" >&2; fail=1; fi
done
case "$WORKLOAD" in Deployment|StatefulSet|DaemonSet) ;; *)
  echo "ERROR: WORKLOAD must be Deployment|StatefulSet|DaemonSet (got '$WORKLOAD')" >&2; fail=1;; esac
case "$SERVICE_TYPE" in ClusterIP|NodePort|LoadBalancer) ;; *)
  echo "ERROR: SERVICE_TYPE must be ClusterIP|NodePort|LoadBalancer (got '$SERVICE_TYPE')" >&2; fail=1;; esac
if ! printf '%s' "$CHART_NAME" | grep -qE '^[a-z0-9]([a-z0-9-]*[a-z0-9])?$'; then
  echo "ERROR: CHART_NAME must be kebab-case DNS-safe (got '$CHART_NAME')" >&2; fail=1; fi
[[ "$fail" -eq 0 ]] || exit 1

[[ -z "$DESCRIPTION" ]] && DESCRIPTION="$CHART_NAME application"
[[ -z "$APP_VERSION" ]] && APP_VERSION="$IMAGE_TAG"
[[ -z "$INGRESS_HOSTNAME" ]] && INGRESS_HOSTNAME="${CHART_NAME}.local"

# Derived booleans
INGRESS_TLS_BOOL="false"; INGRESS_SELFSIGNED_BOOL="false"
case "$INGRESS_TLS" in
  cert-manager) INGRESS_TLS_BOOL="true";;
  self-signed)  INGRESS_TLS_BOOL="true"; INGRESS_SELFSIGNED_BOOL="true";;
  none) ;;
  *) echo "ERROR: INGRESS_TLS must be none|cert-manager|self-signed" >&2; exit 1;;
esac

# --- Plan summary (script-owned confirmation; writes nothing) -----------------
if [[ "$PLAN" -eq 1 ]]; then
  feats=""
  add_feat() { [[ "$2" == "true" ]] && feats="$feats${feats:+, }$1"; }
  add_feat ingress "$INGRESS_ENABLED"
  add_feat persistence "$PERSISTENCE_ENABLED"
  add_feat hpa "$HPA_ENABLED"
  add_feat pdb "$PDB_ENABLED"
  add_feat networkpolicy "$NETWORKPOLICY_ENABLED"
  add_feat metrics "$METRICS_ENABLED"
  add_feat servicemonitor "$SERVICEMONITOR_ENABLED"
  add_feat secrets "$SECRETS_ENABLED"
  add_feat configmap "$CONFIGMAP_ENABLED"
  [[ -z "$feats" ]] && feats="(none)"
  if [[ "$INGRESS_ENABLED" == "true" ]]; then
    ingress_line="$INGRESS_HOSTNAME (class=${INGRESS_CLASS:-default}, tls=$INGRESS_TLS)"
  else
    ingress_line="disabled"
  fi
  cat <<PLAN
==> Helm chart plan (confirm before generating)
    chart:        $CHART_NAME
    description:  $DESCRIPTION
    appVersion:   $APP_VERSION
    image:        $IMAGE_REGISTRY/$IMAGE_REPOSITORY:$IMAGE_TAG  (pullPolicy IfNotPresent)
    workload:     $WORKLOAD   replicas=$REPLICA_COUNT
    service:      $SERVICE_TYPE  port $SERVICE_PORT -> containerPort $CONTAINER_PORT
    ingress:      $ingress_line
    features on:  $feats
    security:     non-root UID $RUN_AS_USER, runAsNonRoot, readOnlyRootFilesystem=$READ_ONLY_ROOT_FS,
                  drop ALL capabilities, seccompProfile=RuntimeDefault, resource requests+limits,
                  liveness + readiness probes, automountServiceAccountToken=false
    environments: values.yaml + values-dev.yaml + values-uat.yaml + values-prod.yaml
    output dir:   $OUT/$CHART_NAME
Run the same command without --plan to generate.
PLAN
  exit 0
fi

# --- sed-escape a replacement string (handle \\ & and the | delimiter) -------
esc() { printf '%s' "$1" | sed -e 's/[\\&|]/\\&/g'; }

# Build the values.yaml sed program once.
val_sed=""
add() { val_sed="$val_sed -e s|%%$1%%|$(esc "$2")|g"; }
add IMAGE_REGISTRY "$IMAGE_REGISTRY"
add IMAGE_REPOSITORY "$IMAGE_REPOSITORY"
add IMAGE_TAG "$IMAGE_TAG"
add CONTAINER_PORT "$CONTAINER_PORT"
add REPLICA_COUNT "$REPLICA_COUNT"
add RUN_AS_USER "$RUN_AS_USER"
add READ_ONLY_ROOT_FS "$READ_ONLY_ROOT_FS"
add SERVICE_TYPE "$SERVICE_TYPE"
add SERVICE_PORT "$SERVICE_PORT"
add INGRESS_ENABLED "$INGRESS_ENABLED"
add INGRESS_CLASS "$INGRESS_CLASS"
add INGRESS_HOSTNAME "$INGRESS_HOSTNAME"
add INGRESS_TLS_BOOL "$INGRESS_TLS_BOOL"
add INGRESS_SELFSIGNED_BOOL "$INGRESS_SELFSIGNED_BOOL"
add PERSISTENCE_ENABLED "$PERSISTENCE_ENABLED"
add PERSISTENCE_SIZE "$PERSISTENCE_SIZE"
add PERSISTENCE_MOUNT "$PERSISTENCE_MOUNT"
add SA_CREATE "$SA_CREATE"
add HPA_ENABLED "$HPA_ENABLED"
add HPA_MIN "$HPA_MIN"
add HPA_MAX "$HPA_MAX"
add HPA_TARGET_CPU "$HPA_TARGET_CPU"
add PDB_ENABLED "$PDB_ENABLED"
add PDB_MIN_AVAILABLE "$PDB_MIN_AVAILABLE"
add NETWORKPOLICY_ENABLED "$NETWORKPOLICY_ENABLED"
add METRICS_ENABLED "$METRICS_ENABLED"
add SERVICEMONITOR_ENABLED "$SERVICEMONITOR_ENABLED"
add METRICS_PORT "$METRICS_PORT"

CHART_DIR="$OUT/$CHART_NAME"
echo "scaffold: chart=$CHART_NAME workload=$WORKLOAD -> $CHART_DIR"
if [[ "$DRYRUN" -eq 1 ]]; then echo "(dry-run: no files written)"; fi

emit() { # emit <src-template> <dest-relative>  (CHARTNAME-substituted copy)
  local src="$TPL/$1" dst="$CHART_DIR/$2"
  [[ -f "$src" ]] || { echo "  ! missing template: $1" >&2; return 1; }
  echo "  + $2"
  [[ "$DRYRUN" -eq 1 ]] && return 0
  mkdir -p "$(dirname "$dst")"
  sed "s|CHARTNAME|$CHART_NAME|g" "$src" > "$dst"
}

[[ "$DRYRUN" -eq 0 ]] && mkdir -p "$CHART_DIR/templates"

# --- Chart.yaml (name/description/appVersion/keyword/maintainer) -------------
echo "  + Chart.yaml"
if [[ "$DRYRUN" -eq 0 ]]; then
  sed -e "s|CHARTNAME|$CHART_NAME|g" \
      -e "s|<one-line description from interview>|$(esc "$DESCRIPTION")|" \
      -e "s|\"<appVersion>\"|\"$(esc "$APP_VERSION")\"|" \
      -e "s|<keyword>|$CHART_NAME|" \
      -e "s|<maintainer or team>|$(esc "$MAINTAINER")|" \
      "$TPL/Chart.yaml" > "$CHART_DIR/Chart.yaml"
fi

# --- values.yaml (rendered from template) ------------------------------------
echo "  + values.yaml"
if [[ "$DRYRUN" -eq 0 ]]; then
  # shellcheck disable=SC2086
  sed $val_sed "$TPL/values.yaml.tmpl" > "$CHART_DIR/values.yaml"
fi

# --- Static / always files ----------------------------------------------------
emit values-dev.yaml  values-dev.yaml
emit values-uat.yaml  values-uat.yaml
emit values-prod.yaml values-prod.yaml
emit values.schema.json values.schema.json
emit dot-helmignore   .helmignore
emit _helpers.tpl     templates/_helpers.tpl
emit service.yaml     templates/service.yaml
emit serviceaccount.yaml templates/serviceaccount.yaml
emit NOTES.txt        templates/NOTES.txt
emit extra-list.yaml  templates/extra-list.yaml

# --- Workload (exactly one) ---------------------------------------------------
case "$WORKLOAD" in
  Deployment)  emit deployment.yaml  templates/deployment.yaml;;
  StatefulSet) emit statefulset.yaml templates/statefulset.yaml
               emit headless-service.yaml templates/headless-service.yaml;;
  DaemonSet)   emit daemonset.yaml   templates/daemonset.yaml;;
esac

# Deployment + persistence needs an explicit PVC (StatefulSet uses volumeClaimTemplates).
if [[ "$WORKLOAD" == "Deployment" && "$PERSISTENCE_ENABLED" == "true" ]]; then
  emit pvc.yaml templates/pvc.yaml
fi

# --- Feature templates -------------------------------------------------------
# Always emitted; each self-guards on its own value (renders nothing when off).
# This is what lets the env overlays ENABLE hardening (PDB, NetworkPolicy, HPA,
# ingress) in prod even when the feature was off at generation time — the toggle
# only sets the default in values.yaml, not whether the template exists. Token
# cost is zero: bodies are copied on disk and never read by the model.
emit ingress.yaml        templates/ingress.yaml        # gated by ingress.enabled
emit pdb.yaml            templates/pdb.yaml            # gated by pdb.create
emit networkpolicy.yaml  templates/networkpolicy.yaml  # gated by networkPolicy.enabled
emit servicemonitor.yaml templates/servicemonitor.yaml # gated by metrics.serviceMonitor.enabled
# HPA hardcodes kind: Deployment, so emit it only for a Deployment (its value
# gate, autoscaling.enabled, still controls whether it renders).
[[ "$WORKLOAD" == "Deployment" ]] && emit hpa.yaml templates/hpa.yaml
# Content-driven extras: only when chosen (no overlay enables these).
[[ "$SECRETS_ENABLED" == "true" ]]        && emit secrets.yaml        templates/secrets.yaml
[[ "$CONFIGMAP_ENABLED" == "true" ]]      && emit configmap.yaml      templates/configmap.yaml

echo "scaffold: done."
[[ "$DRYRUN" -eq 0 ]] && echo "Next: review values.yaml, run helm lint '$CHART_DIR', then helm-docs for README.md."
exit 0
