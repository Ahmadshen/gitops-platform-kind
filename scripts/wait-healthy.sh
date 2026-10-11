#!/usr/bin/env bash
# Wait until every Argo CD Application is Synced and Healthy.
set -euo pipefail
TIMEOUT=${TIMEOUT:-900}
EXPECTED=${EXPECTED:-5} # root, kyverno, policies, podinfo-dev, podinfo-prod (+ monitoring)
deadline=$(( $(date +%s) + TIMEOUT ))

status() {
  kubectl -n argocd get applications.argoproj.io \
    -o custom-columns='APP:.metadata.name,SYNC:.status.sync.status,HEALTH:.status.health.status' 2>/dev/null
}

while true; do
  apps=$(kubectl -n argocd get applications.argoproj.io -o json 2>/dev/null || echo '{"items":[]}')
  total=$(jq '.items | length' <<<"$apps")
  ready=$(jq '[.items[] | select(.status.sync.status=="Synced" and .status.health.status=="Healthy")] | length' <<<"$apps")
  if [ "$total" -ge "$EXPECTED" ] && [ "$ready" -eq "$total" ]; then
    status
    echo "All ${total} applications Synced and Healthy."
    exit 0
  fi
  if [ "$(date +%s)" -ge "$deadline" ]; then
    status
    echo "Timed out after ${TIMEOUT}s (${ready}/${total} ready)." >&2
    kubectl -n argocd get applications.argoproj.io -o json \
      | jq -r '.items[] | select(.status.health.status!="Healthy" or .status.sync.status!="Synced") | "\(.metadata.name): \(.status.conditions // [] | map(.message) | join("; ")) \(.status.operationState.message // "")"' >&2
    exit 1
  fi
  echo "waiting: ${ready}/${total} applications ready"
  sleep 10
done
