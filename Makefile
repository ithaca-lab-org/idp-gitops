.PHONY: check
check: ## lint YAML and check Application structure
	yamllint --strict .
	./scripts/check.sh
