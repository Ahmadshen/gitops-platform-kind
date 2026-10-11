#!/usr/bin/env bash
# Offline checks: no cluster needed.
set -euo pipefail
cd "$(dirname "$0")/.."
source versions.env
mkdir -p build

echo ">> helm lint root app-of-apps"
helm lint bootstrap/root
helm template platform-root bootstrap/root > build/root.yaml

echo ">> Kyverno policy unit tests"
kyverno test tests/policies

echo ">> Rendered apps comply with every policy (as Argo CD deploys them: no Helm test hooks)"
for env in $(awk '/- name:/ {print $3}' bootstrap/root/values.yaml); do
  version=$(awk -v env="$env" '$0 ~ "name: "env {getline; print $2}' bootstrap/root/values.yaml | tr -d '"')
  helm template podinfo podinfo --repo https://stefanprodan.github.io/podinfo --version "$version" \
    --namespace "podinfo-${env}" --skip-tests -f "apps/podinfo/envs/${env}/values.yaml" > "build/podinfo-${env}.yaml"
  kyverno apply policies/ --resource "build/podinfo-${env}.yaml" --policy-report=false 2>&1 | tee /dev/stderr | grep -q "fail: 0, warn: 0, error: 0" \
    || { echo "podinfo ${env} violates policy" >&2; exit 1; }
done

echo ">> Schema validation (Kubernetes + Argo CD + Kyverno CRDs)"
docker run --rm -v "$PWD":/w -w /w "ghcr.io/yannh/kubeconform:${KUBECONFORM_VERSION}" -strict -summary \
  -schema-location default \
  -schema-location 'https://raw.githubusercontent.com/datreeio/CRDs-catalog/main/{{.Group}}/{{.ResourceKind}}_{{.ResourceAPIVersion}}.json' \
  build/root.yaml policies/ build/podinfo-*.yaml
