# One entry point for local and CI runs: the CI verify job calls `make verify`,
# next to the shared workflows. Offline: no AWS credentials and
# no AWS API calls. The first
# run downloads npm packages, Terraform providers, the tflint AWS ruleset,
# base images and the Trivy vulnerability database.

SHELL := /usr/bin/env bash
.SHELLFLAGS := -euo pipefail -c
.DEFAULT_GOAL := help

IMAGE ?= harbor-stock-api:local
CHECKOV_VERSION := 3.3.19
TF_STACKS := infra/terraform/registry infra/terraform/service
TFLINT_CONFIG := $(CURDIR)/.tflint.hcl

.PHONY: help verify app-test private-plan-test image smoke tf-fmt tf-verify hadolint checkov trivy test-live clean

help: ## List targets
	@grep -E '^[a-z-]+:.*## ' $(MAKEFILE_LIST) | awk 'BEGIN {FS = ":.*## "} {printf "  %-18s %s\n", $$1, $$2}'

verify: app-test private-plan-test image smoke tf-verify hadolint checkov trivy ## Run every offline check
	@echo "verify: all checks passed"

app-test: ## Unit tests of the API (TypeScript build + node:test)
	cd app && npm ci --no-audit --no-fund && npm test

private-plan-test: ## Unit tests of the live-test pre-flight (scripts/check_private_plan.py)
	python3 -m unittest discover -s tests -p 'test_check_private_plan.py'

image: ## Build the container image (multi-stage; the build stage runs the tests again)
	docker build --tag $(IMAGE) --build-arg APP_VERSION=local app

smoke: ## Run the image with the ECS constraints and probe it
	scripts/smoke-test.sh $(IMAGE)

tf-fmt: ## Rewrite Terraform files to canonical format
	terraform fmt -recursive infra/terraform

tf-verify: ## fmt check, validate, tflint and mocked terraform test (incl. live_private) for each stack
	terraform fmt -check -recursive infra/terraform
	for stack in $(TF_STACKS); do \
	  echo "--- $$stack"; \
	  terraform -chdir=$$stack init -backend=false -input=false > /dev/null; \
	  terraform -chdir=$$stack validate; \
	  (cd $$stack && tflint --init --config=$(TFLINT_CONFIG) > /dev/null && tflint --config=$(TFLINT_CONFIG)); \
	  terraform -chdir=$$stack test; \
	done

hadolint: ## Lint the Dockerfile
	hadolint app/Dockerfile

checkov: ## Policy checks on Terraform, the Dockerfile and the workflows (.checkov.yaml)
	uvx checkov==$(CHECKOV_VERSION) --config-file .checkov.yaml

trivy: ## Trivy misconfiguration scan of the repo and vulnerability scan of the image
	trivy config --quiet --exit-code 1 --severity HIGH,CRITICAL --skip-dirs '**/.terraform' --skip-dirs '**/node_modules' .
	trivy image --quiet --exit-code 1 --severity HIGH,CRITICAL --ignore-unfixed $(IMAGE)

test-live: ## Manual: deploy to the maintainer's dev account, verify, destroy (see docs/live-test.md)
	scripts/test-live.sh

clean: ## Remove build output and local Terraform caches
	rm -rf app/dist app/node_modules infra/terraform/*/.terraform
