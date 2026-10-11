#!/usr/bin/env bash
# Create the kind cluster, install Argo CD, and hand everything else to GitOps.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env

CLUSTER=gitops-platform
# Default to this checkout's GitHub remote and exact commit, so what you run is what you see.
REPO_URL=${REPO_URL:-$(git remote get-url origin | sed -E 's#^git@github(-[a-z]+)?:#https://github.com/#')}
REVISION=${REVISION:-$(git rev-parse HEAD)}
MONITORING=${MONITORING:-true}

echo ">> repo=${REPO_URL} revision=${REVISION} monitoring=${MONITORING}"

if ! kind get clusters 2>/dev/null | grep -qx "${CLUSTER}"; then
  kind create cluster --config kind/cluster.yaml --wait 120s
fi
kubectl config use-context "kind-${CLUSTER}" >/dev/null

echo ">> Argo CD (chart ${ARGOCD_CHART_VERSION})"
helm upgrade --install argocd argo-cd \
  --repo https://argoproj.github.io/argo-helm --version "${ARGOCD_CHART_VERSION}" \
  --namespace argocd --create-namespace \
  --values bootstrap/argocd-values.yaml \
  --wait --timeout 10m

echo ">> root app-of-apps"
sed -e "s#__REPO_URL__#${REPO_URL}#g" \
    -e "s#__REVISION__#${REVISION}#g" \
    -e "s#__MONITORING__#${MONITORING}#g" \
    bootstrap/root-app.yaml.tpl | kubectl apply -f -

echo "Bootstrapped. Next: make wait"
