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

while [[ $# -gt 0 ]]; do
  case "$1" in
    --answers)   ANSWERS="$2"; shift 2;;
    --out)       OUT="$2"; shift 2;;
    --templates) TPL="$2"; shift 2;;
    --dry-run)   DRYRUN=1; shift;;
    -h|--help)   sed -n '2,30p' "$0"; exit 0;;
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
REPLICA_COUNT="1"; RUN_AS_USER="1001"; READ_ONLY_ROOT_FS="true"
MAINTAINER="team"
INGRESS_ENABLED="false"; INGRESS_HOSTNAME=""; INGRESS_CLASS=""; INGRESS_TLS="none"
PERSISTENCE_ENABLED="false"; PERSISTENCE_SIZE="8Gi"; PERSISTENCE_MOUNT="/data"
HPA_ENABLED="false"; HPA_MIN="2"; HPA_MAX="5"; HPA_TARGET_CPU="80"
PDB_ENABLED="false"; PDB_MIN_AVAILABLE="1"
NETWORKPOLICY_ENABLED="false"
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

# --- Conditional feature templates -------------------------------------------
[[ "$INGRESS_ENABLED" == "true" ]]        && emit ingress.yaml        templates/ingress.yaml
[[ "$PDB_ENABLED" == "true" ]]            && emit pdb.yaml            templates/pdb.yaml
[[ "$NETWORKPOLICY_ENABLED" == "true" ]]  && emit networkpolicy.yaml  templates/networkpolicy.yaml
[[ "$SERVICEMONITOR_ENABLED" == "true" ]] && emit servicemonitor.yaml templates/servicemonitor.yaml
[[ "$SECRETS_ENABLED" == "true" ]]        && emit secrets.yaml        templates/secrets.yaml
[[ "$CONFIGMAP_ENABLED" == "true" ]]      && emit configmap.yaml      templates/configmap.yaml
# HPA only makes sense for Deployment (StatefulSet/DaemonSet not autoscaled here).
if [[ "$HPA_ENABLED" == "true" && "$WORKLOAD" == "Deployment" ]]; then
  emit hpa.yaml templates/hpa.yaml
fi

echo "scaffold: done."
[[ "$DRYRUN" -eq 0 ]] && echo "Next: review values.yaml, run helm lint '$CHART_DIR', then helm-docs for README.md."
exit 0
