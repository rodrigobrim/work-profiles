#!/usr/bin/env bash

usage() {
  cat <<EOF
Usage: $0 -f cluster-list-file -n namespace -s secret-name -k secret-key -v new-value -m [auto-apply|dry-run]

  -f CLUSTER_LIST_FILE   Plain text file with the list of clusters to update (one per line). The iteration uses 'kubectx' to switch contexts, so cluster names should match the context names in kubeconfig.
  -n NAMESPACE   Namespace to update secrets in
  -s SECRET_NAME Name of the secret to update
  -k SECRET_KEY  Key starting with which to find the value to update (e.g. 'DB_' to update all keys starting with 'DB_')
  -v NEW_VALUE   New value to set for the specified secret key
  -m MODE        Mode of operation: 'auto-confirm' to apply changes without confirmation, 'dry-run' to show what would be updated without making changes
EOF
  exit 1
}

pushd "$(dirname -- "${BASH_SOURCE[0]}")" >/dev/null || exit 1
source manage-secrets.sh || exit 1
popd >/dev/null

# parse flags
while getopts "f:n:s:k:v:m:h" opt; do
  case "$opt" in
    f) CLUSTERS="$OPTARG" ;;
    n) NAMESPACE="$OPTARG" ;;
    s) SECRET_NAME="$OPTARG" ;;
    k) SECRET_KEY="$OPTARG" ;;
    v) NEW_VALUE="$OPTARG" ;;
    m) MODE="$OPTARG" ;;
    h|*) usage ;;
  esac
done

if [[ -z "$CLUSTERS" || -z "$NAMESPACE" || -z "$SECRET_NAME" || -z "$SECRET_KEY" || -z "$NEW_VALUE" ]]; then
  usage
fi

MODE="${MODE:-standard}"
TIME=`date +"%Y%m%d-%H%M"`
echo "Running in $MODE mode."

set -euo pipefail

while IFS= read -r CLUSTER; do
  kubectx "$CLUSTER" 2>&1 >/dev/null || { echo "Failed to switch to cluster $CLUSTER. Skipping."; continue; }
  OLD_VALUE=`k-decode-secret "$SECRET_NAME" "$SECRET_KEY" $NAMESPACE 2>/dev/null || { echo "Failed to get secret. Skipping."; continue; }`
  OLD_VALUE=`echo "$OLD_VALUE" | awk '{print $2}'`
  # [[ "$OLD_VALUE" == "$NEW_VALUE" ]] && continue
  if [[ "$MODE" == "dry-run" ]]; then
    echo "DRY RUN: Would update key $SECRET_KEY from '$OLD_VALUE' to '$NEW_VALUE' in $CLUSTER"
    echo "$CLUSTER" >> /tmp/k8s-to-update-clusters
    continue
  fi
  # Backup the existing secret before updating
  # kubectl get secret $SECRET_NAME -n $NAMESPACE -o yaml > "${SECRET_NAME}-${CLUSTER}-$TIME.yaml"
  kubectl rollout restart statefulset.apps vantage-kubernetes-agent -n $NAMESPACE
  # kubectl wait --for=condition=available statefulset.apps/vantage-kubernetes-agent -n $NAMESPACE --timeout=5m || { echo "Warning: Timeout waiting for vantage-kubernetes-agent to become available after restart in cluster $CLUSTER. Please check the rollout status manually."; exit 1; }
  continue
  if [[ "$MODE" != "auto-confirm" ]]; then
    read -p "Update secret $SECRET_NAME/$SECRET_KEY from '$OLD_VALUE' to '$NEW_VALUE' in cluster $CLUSTER? (y/N) " -n 1 -r
    echo
    [[ ! $REPLY =~ ^[Yy]$ ]] && echo "Skipping cluster $CLUSTER." && continue
  fi
  echo "Updating secret $SECRET_NAME/$SECRET_KEY from '$OLD_VALUE' to '$NEW_VALUE' in cluster $CLUSTER"
  k-update-secret-key "$SECRET_NAME" "$SECRET_KEY" "$NEW_VALUE" $NAMESPACE
  exit 1
done < "$CLUSTERS"
