SHELL := /bin/bash

TEAL = $(shell printf '%b' "\033[0;36m")
GREEN = $(shell printf '%b' "\033[0;32m")
RED = $(shell printf '%b' "\033[0;31m")
NO_COLOUR = $(shell printf '%b' "\033[m")

GOBIN = $(shell pwd)/bin
PACKAGES = $(shell go list ./... | grep -v /vendor/)
UPPER_CASE_REPO_NAME = $(shell $(	REPO_NAME) | sed -r 's/\<./\U&/g')
AWS := $(shell command aws --version 2> /dev/null)
DONE = printf '%b\n' ">> $(GREEN)$@ done ✓"

DOCKER_TEAM_NAME ?= operations-reliability
DOCKER_TAG ?= latest

ifneq ("$(CIRCLE_SHA1)", "")
VCS_SHA := $(CIRCLE_SHA1)
else
VCS_SHA = $(shell git rev-parse HEAD)
endif

ifneq ("$(CIRCLE_BUILD_NUM)", "")
BUILD_NUMBER := $(CIRCLE_BUILD_NUM)
else
BUILD_NUMBER := n/a
endif

ifneq ("$(CIRCLE_PROJECT_REPONAME)", "")
REPO_NAME := $(CIRCLE_PROJECT_REPONAME)
else
REPO_NAME = $(shell basename `git rev-parse --show-toplevel`)
endif

all: format build test

test: ## Run the tests 🚀.
	@printf '%b\n' ">> $(TEAL)running tests"
	go test -short $(PACKAGES)
	@$(DONE)

style: ## Check the formatting of the Go source code.
	@printf '%b\n' ">> $(TEAL)checking code style"
	@! gofmt -d $(shell find . -path ./vendor -prune -o -name '*.go' -print) | grep '^'
	@$(DONE)

format: ## Format the Go source code.
	@printf '%b\n' ">> $(TEAL)formatting code"
	go fmt $(PACKAGES)
	@$(DONE)

vet: ## Examine the Go source code.
	@printf '%b\n' ">> $(TEAL)vetting code"
	go vet $(PACKAGES)
	@$(DONE)

.PHONY: security
security: ## Perform security scans. Needs to be run in an environment with the snyk CLI tool.
security: _security-dependencies

_security-login:

_security-login-web: ## Login to snyk if not on CI.
	@printf '%b\n' ">> $(TEAL)Not on CI, logging into Snyk"
	snyk auth

ifeq ($(CI),)
_security-login: _security-login-web
endif

_security-dependencies: _security-login ## Scan dependencies for security vulnerabilities.
	# TODO: enable once snyk support go modules https://github.com/snyk/snyk/issues/354
	# @printf '%b\n' ">> $(TEAL)scanning dependencies for vulnerabilities"
	# snyk test --org=reliability-engineering
	# @$(DONE)

.PHONY: security-monitor
security-monitor: ## Update latest monitored dependencies in snyk. Needs to be run in an environment with the snyk CLI tool.
security-monitor: _security-dependencies-monitor

_security-dependencies-monitor: ## Update snyk monitored dependencies.
	# TODO: enable once snyk support go modules https://github.com/snyk/snyk/issues/354
	# @printf '%b\n' ">> $(TEAL)updating snyk dependencies"
	# snyk monitor --org=reliability-engineering
	# @$(DONE)

build: ## Build the Docker image.
	@printf '%b\n' ">> $(TEAL)building the docker image"
	docker build \
		-t "financial-times/$(REPO_NAME):$(VCS_SHA)" \
		--build-arg BUILD_DATE="$(shell date '+%FT%T.%N%:z')" \
		--build-arg VCS_SHA=$(VCS_SHA) \
		--build-arg BUILD_NUMBER=$(BUILD_NUMBER) \
		.
	@$(DONE)

run: ## Run the Docker image.
	@printf '%b\n' ">> $(TEAL)running the docker image"
	docker run \
		-e AWS_ACCESS_KEY_ID=$(AWS_ACCESS_KEY_ID) \
		-e AWS_SECRET_ACCESS_KEY=$(AWS_SECRET_ACCESS_KEY) \
		-e AWS_REGION=$(AWS_REGION) \
		-v $(PWD)/out:/root/out \
		"financial-times/$(REPO_NAME):$(VCS_SHA)" $(ARGS) --config.write-to=out/ecs_file_sd.yml
	@$(DONE)

publish: ## Push the docker image to the FT private repository.
	@printf '%b\n' ">> $(TEAL)pushing the docker image"
	docker tag "financial-times/$(REPO_NAME):$(VCS_SHA)" "nexus.in.ft.com:5000/$(DOCKER_TEAM_NAME)/$(REPO_NAME):$(DOCKER_TAG)"
	docker push "nexus.in.ft.com:5000/$(DOCKER_TEAM_NAME)/$(REPO_NAME):$(DOCKER_TAG)"
	@$(DONE)

validate-aws-stack-command:
	@if [[ -z "$(AWS)" ]]; then echo "❌ $(RED)AWS is not available please install aws-cli. See https://aws.amazon.com/cli/" && exit 1; fi
	@if [[ -z "$(ECS_CLUSTER_NAME)" ]]; then echo "❌ $(RED)ECS_CLUSTER_NAME is not available. Please specify the ECS cluster to deploy to" && exit 1; fi
	@if [[ -z "$(SPLUNK_HEC_TOKEN)" ]]; then echo "❌ $(RED)SPLUNK_HEC_TOKEN is not available. $(NO_COLOUR)This is a required variable for cloudformation deployments" && exit 1; fi

deploy-stack: validate-aws-stack-command ## Create the cloudformation stack
	@printf '%b\n' ">> $(TEAL)deploying cloudformation stack"
	@aws cloudformation deploy \
		--stack-name "$(ECS_CLUSTER_NAME)-service-$(REPO_NAME)" \
		--template-file deployments/cloudformation.yml \
		--parameter-overrides \
			ParentClusterStackName=$(ECS_CLUSTER_NAME) \
			SplunkHecToken=$(SPLUNK_HEC_TOKEN) \
			DockerRevision="$(DOCKER_TAG)" \
		--no-fail-on-empty-changeset \
		--tags \
        	environment="p" \
        	systemCode="$(REPO_NAME)" \
        	teamDL="reliability.engineering@ft.com"
	@$(DONE)

help: ## Show this help message.
	@printf '%b\n' "usage: make [target] ..."
	@printf '%b\n' ""
	@printf '%b\n' "targets:"
	@# replace the first : with £ to avoid splitting columns on URLs
	@grep -Eh '^[^_].+?:\ ##\ .+' ${MAKEFILE_LIST} | cut -d ' ' -f '1 3-' | sed 's/^(.+?):/$1/' | sed 's/:/£/' | column -t -c 2 -s '£'

.PHONY: all style format build test vet deploy-stack
