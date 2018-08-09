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
	@if [[ -z "$(SPLUNK_HEC_TOKEN)" ]]; then echo "❌ $(RED)SPLUNK_HEC_TOKEN is not available. $(NO_COLOUR)This is a required variable for cloudformation deployments" && exit 1; fi

deploy-stack: validate-aws-stack-command ## Create the cloudformation stack
	@printf '%b\n' ">> $(TEAL)deploying cloudformation stack"
	@aws cloudformation deploy \
		--stack-name "mon-agg-ecs-service-$(REPO_NAME)" \
		--template-file deployments/cloudformation.yml \
		--parameter-overrides \
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
	@grep -Eh '^.+:\ ##\ .+' ${MAKEFILE_LIST} | column -t -s ':#'

.PHONY: all style format build test vet deploy-stack
