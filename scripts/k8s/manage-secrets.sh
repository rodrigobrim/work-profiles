#!/usr/bin/env bash

# Utility function to manage Kubernetes secrets.
# Import it into your shell with: source k8s-manage-secrets.sh

_k-decode-secret () {
  secrets=`echo $1 | base64 -d`
  for s in $secrets; do
    key=`echo $s | cut -d',' -f1`
    hash=`echo $s | cut -d',' -f2`
    echo "$key: `echo $hash | base64 -d`"
  done
}

k-decode-secret () {

  # Usage: k-decode-secret <secret-name> [keys-starts-with]
  
  # It can decode all keys or only those that start with a specified prefix.
  # You can use it like:
  #   k-decode-secret my-secret
  #   k-decode-secret my-secret DB_
  
  SECRET=$1
  START_WITH=$2
  NAMESPACE=$3
  if [ -z "$SECRET" ]; then
    echo "Usage: k-decode-secret <secret-name> [keys-starts-with]"
    return
  fi
  if [ -n "$NAMESPACE" ]; then
    NAMESPACE="-n $NAMESPACE"
  fi
  if [ -z "$START_WITH" ]; then
    _k-decode-secret `kubectl get secret $SECRET $NAMESPACE -o json | jq -r '.data | to_entries | .[] | [.key, .value] | join(",")' | base64 -b0`
    return
  fi
  _k-decode-secret `kubectl get secret $SECRET $NAMESPACE -o json | jq -r --arg s "$START_WITH" '.data | with_entries(select(.key | startswith($s))) | to_entries | .[] | [.key, .value] | join(",")' | base64 -b0`
}

_k-patch-secret () {
  # Args: <secret-name> <json-patch> [namespace]
  SECRET=$1
  PATCH=$2
  NAMESPACE=$3

  if [ -n "$NAMESPACE" ]; then
    NAMESPACE="-n $NAMESPACE"
  else
    NAMESPACE=""
  fi

  kubectl patch secret "$SECRET" $NAMESPACE --type merge -p "$PATCH"
}

k-update-secret-key () {
  # Usage: k-update-secret-key <secret-name> <key> <value> [namespace]
  #
  # Example:
  #   k-update-secret-key my-secret DB_PASSWORD "newpass"
  #   k-update-secret-key my-secret DB_PASSWORD "newpass" my-namespace

  SECRET=$1
  KEY=$2
  VALUE=$3
  NAMESPACE=$4

  if [ -z "$SECRET" ] || [ -z "$KEY" ] || [ -z "$VALUE" ]; then
    echo "Usage: k-update-secret-key <secret-name> <key> <value> [namespace]"
    return 1
  fi

  B64_VALUE="$(printf "%s" "$VALUE" | base64 -b0)"
  PATCH="$(jq -cn --arg k "$KEY" --arg v "$B64_VALUE" '{data: {($k): $v}}')"

  _k-patch-secret "$SECRET" "$PATCH" "$NAMESPACE"
}