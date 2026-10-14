.PHONY: check
check: ## lint YAML and check Application structure
	yamllint --strict .
	./scripts/check.sh

.PHONY: render-check
render-check: ## render Istio charts like Argo CD does and assert GKE settings (needs helm + network)
	./scripts/render-check.sh
