#!/usr/bin/env bash
# Prove the platform does what it claims: apps serve traffic, environments run
# their promoted versions, policies block bad workloads, and Git wins over drift.
set -euo pipefail
cd "$(dirname "$0")/.."
pass() { echo "PASS: $*"; }
fail() { echo "FAIL: $*" >&2; exit 1; }

expected_version() { # env -> chartVersion from the root chart values
  awk -v env="$1" '$0 ~ "name: "env {getline; print $2}' bootstrap/root/values.yaml | tr -d '"'
}

# 1. Both environments are up, and prod is HA.
for env in dev prod; do
  kubectl -n "podinfo-${env}" rollout status deploy/podinfo --timeout=180s >/dev/null
done
[ "$(kubectl -n podinfo-prod get deploy podinfo -o jsonpath='{.status.readyReplicas}')" = "2" ] \
  && pass "prod runs 2 ready replicas" || fail "prod should run 2 replicas"

# 2. Each environment serves the version promoted to it.
for env in dev prod; do
  want=$(expected_version "$env")
  kubectl -n "podinfo-${env}" port-forward svc/podinfo 19898:9898 >/dev/null 2>&1 &
  pf=$!
  sleep 3
  got=$(curl -fsS localhost:19898/version | jq -r .version)
  kill "$pf" 2>/dev/null || true
  wait "$pf" 2>/dev/null || true
  [ "$got" = "$want" ] && pass "${env} serves podinfo ${got}" || fail "${env} serves ${got}, expected ${want}"
done

# 3. Admission control: a :latest image is rejected by Kyverno.
if out=$(kubectl -n podinfo-dev run bad-pod --image=nginx:latest --dry-run=server 2>&1); then
  fail "a :latest pod was admitted"
fi
grep -q "disallow-latest-tag" <<<"$out" && pass "Kyverno blocked a :latest image" || fail "unexpected rejection: $out"

# 4. Self-heal: manual drift is reverted to what Git declares.
kubectl -n podinfo-prod scale deploy/podinfo --replicas=5 >/dev/null
for _ in $(seq 1 30); do
  sleep 4
  [ "$(kubectl -n podinfo-prod get deploy podinfo -o jsonpath='{.spec.replicas}')" = "2" ] && {
    pass "Argo CD reverted manual scale-up (5 -> 2)"; exit 0; }
done
fail "drift was not reverted"
