.PHONY: help up wait smoke e2e validate ui grafana down

help: ## Show targets
	@grep -E '^[a-z0-9]+:.*##' $(MAKEFILE_LIST) | awk -F':.*## ' '{printf "  %-9s %s\n", $$1, $$2}'

up: ## Create kind cluster, install Argo CD, apply the root app (MONITORING=false for a lighter run)
	./scripts/bootstrap.sh

wait: ## Wait until every Argo CD Application is Synced + Healthy
	EXPECTED=$$([ "$${MONITORING:-true}" = "true" ] && echo 6 || echo 5) ./scripts/wait-healthy.sh

smoke: ## Traffic, promoted versions, policy enforcement, drift self-heal
	./scripts/smoke-test.sh

e2e: up wait smoke ## Full end-to-end run

validate: ## Offline: helm lint, Kyverno tests, app policy compliance, schema validation
	./scripts/validate.sh

ui: ## Argo CD UI on http://localhost:8080 (user: admin)
	@echo "password: $$(kubectl -n argocd get secret argocd-initial-admin-secret -o jsonpath='{.data.password}' | base64 -d)"
	kubectl -n argocd port-forward svc/argocd-server 8080:80

grafana: ## Grafana on http://localhost:3000 (admin / admin, local only)
	kubectl -n monitoring port-forward svc/monitoring-grafana 3000:80

down: ## Delete the kind cluster
	kind delete cluster --name gitops-platform
