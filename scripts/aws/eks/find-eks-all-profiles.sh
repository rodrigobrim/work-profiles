#!/usr/bin/env bash
set -euo pipefail

# Any valid region works as the "bootstrap" for DescribeRegions.
BOOTSTRAP_REGION="${BOOTSTRAP_REGION:-us-east-1}"

# If you only want certain profiles (e.g. devops_team), set:
#   PROFILE_FILTER_REGEX='devops_team$'
PROFILE_FILTER_REGEX="${PROFILE_FILTER_REGEX:-.*}"

# Grab profile names from ~/.aws/credentials (works well with gimme-aws-creds output)
mapfile -t PROFILES < <(awk -F'[][]' '/^\[/{print $2}' ~/.aws/credentials | grep -E "$PROFILE_FILTER_REGEX" | sort -u)

if [ ${#PROFILES[@]} -eq 0 ]; then
  echo "No profiles found in ~/.aws/credentials matching regex: $PROFILE_FILTER_REGEX" >&2
  exit 1
fi

for profile in "${PROFILES[@]}"; do
  # Identify account (skip profile if not usable)
  account_id="$(aws sts get-caller-identity --profile "$profile" --query 'Account' --output text 2>/dev/null || true)"
  if [[ -z "$account_id" || "$account_id" == "None" ]]; then
    echo "SKIP (cannot auth): profile=$profile" >&2
    continue
  fi

  # Enumerate enabled regions (requires specifying *some* region)
  regions="$(aws ec2 describe-regions \
    --profile "$profile" \
    --region "$BOOTSTRAP_REGION" \
    --query 'Regions[].RegionName' \
    --output text 2>/dev/null || true)"

  if [[ -z "$regions" ]]; then
    echo "SKIP (cannot list regions): account=$account_id profile=$profile" >&2
    continue
  fi

  for region in $regions; do
    # list-clusters: if no permission, returns AccessDenied; if none exist, returns empty.
    clusters="$(aws eks list-clusters \
      --profile "$profile" \
      --region "$region" \
      --query 'clusters' \
      --output text 2>/dev/null || true)"

    if [[ -n "$clusters" && "$clusters" != "None" ]]; then
      for c in $clusters; do
        # Optional: fetch ARN (costs an API call per cluster; comment out if you want it faster)
        arn="$(aws eks describe-cluster \
          --profile "$profile" \
          --region "$region" \
          --name "$c" \
          --query 'cluster.arn' \
          --output text 2>/dev/null || echo "")"

        if [[ -n "$arn" && "$arn" != "None" ]]; then
          echo "account=$account_id profile=\"$profile\" region=$region cluster=$c arn=$arn"
        else
          echo "account=$account_id profile=\"$profile\" region=$region cluster=$c"
        fi
      done
    fi
  done
done