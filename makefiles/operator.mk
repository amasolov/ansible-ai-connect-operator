# operator.mk — Ansible AI Connect Operator specific targets and variables
#
# This file is NOT synced across repos. Each operator maintains its own.

#@ Operator Variables

VERSION ?= $(shell git describe --tags 2>/dev/null || echo 0.1.0)
IMAGE_TAG_BASE ?= quay.io/ansible/ansible-ai-connect
IMG = $(IMAGE_TAG_BASE)-operator:$(VERSION)
NAMESPACE ?= ansible-ai-connect
DEPLOYMENT_NAME ?= ansible-ai-connect-operator-controller-manager

# Feature flags
BUILD_IMAGE ?= true
CREATE_CR ?= false

# Teardown configuration
TEARDOWN_CR_KINDS ?= ansibleaiconnect ansiblemcpconnect
TEARDOWN_BACKUP_KINDS ?=
TEARDOWN_RESTORE_KINDS ?=
OLM_SUBSCRIPTIONS ?=

##@ Ansible AI Connect Operator

.PHONY: operator-up
operator-up: _operator-build-and-push _operator-deploy _operator-post-deploy ## AI Connect-specific deploy

.PHONY: _operator-build-and-push
_operator-build-and-push:
	@if [ "$(BUILD_IMAGE)" != "true" ]; then \
		echo "Skipping image build (BUILD_IMAGE=false)"; \
		exit 0; \
	fi; \
	$(MAKE) dev-build; \
	echo "Pushing $(DEV_IMG):$(DEV_TAG)..."; \
	$(_CONTAINER_CMD) push $(DEV_IMG):$(DEV_TAG)

.PHONY: _operator-deploy
_operator-deploy: kustomize
	@$(MAKE) pre-deploy-cleanup
	@echo "Deploying operator via kustomize..."
	@cd config/default && $(KUSTOMIZE) edit set namespace $(NAMESPACE)
	@$(MAKE) deploy IMG=$(DEV_IMG):$(DEV_TAG)

.PHONY: _operator-post-deploy
_operator-post-deploy:
	@echo "Waiting for operator pods to be ready..."
	@ATTEMPTS=0; \
	while [ $$ATTEMPTS -lt 30 ]; do \
		READY=$$($(KUBECTL) get deployment $(DEPLOYMENT_NAME) -n $(NAMESPACE) \
			-o jsonpath='{.status.readyReplicas}' 2>/dev/null); \
		DESIRED=$$($(KUBECTL) get deployment $(DEPLOYMENT_NAME) -n $(NAMESPACE) \
			-o jsonpath='{.status.replicas}' 2>/dev/null); \
		if [ -n "$$READY" ] && [ -n "$$DESIRED" ] && [ "$$READY" = "$$DESIRED" ] && [ "$$READY" -gt 0 ]; then \
			echo "All pods ready ($$READY/$$DESIRED)."; \
			break; \
		fi; \
		echo "Pods not ready ($$READY/$$DESIRED). Waiting..."; \
		ATTEMPTS=$$((ATTEMPTS + 1)); \
		sleep 10; \
	done; \
	if [ $$ATTEMPTS -ge 30 ]; then \
		echo "ERROR: Timed out waiting for operator pods to be ready (5 minutes)." >&2; \
		exit 1; \
	fi

##@ Release

.PHONY: generate-operator-yaml
generate-operator-yaml: kustomize ## Generate operator.yaml with image tag $(VERSION)
	@cd config/manager && $(KUSTOMIZE) edit set image controller=quay.io/ansible/ansible-ai-connect-operator:${VERSION}
	@$(KUSTOMIZE) build config/default > ./operator.yaml
	@echo "Generated operator.yaml with image tag $(VERSION)"
