EASYBAR_KIT_ROOT ?= ../easybar-kit
SWIFT ?= swift
PRETTIER ?= npx --yes prettier@3.9.6
PRETTIER_MD_SOURCES := README.md
PRETTIER_YAML_SOURCES := ".github/**/*.{yml,yaml}"
PRETTIER_JSON_SOURCES := ".github/**/*.json"

DIST_DIR ?= dist
BUNDLE_ID ?= io.github.gi8lino.easybar
ARCH ?= universal
VERSION ?= dev
LOCAL_INSTALL_ARCH ?= $(shell uname -m)
LOCAL_APP_DIR ?= $(HOME)/Applications
LOCAL_BIN_DIR ?= $(HOME)/.local/bin
LOCAL_AGENT_DIR ?= $(HOME)/Library/Application Support/EasyBar/Agents
LOCAL_LAUNCH_AGENT_DIR ?= $(HOME)/Library/LaunchAgents
LOCAL_LOG_DIR ?= $(HOME)/Library/Logs/EasyBar
LOCAL_STATE_DIR ?= $(HOME)/Library/Application Support/EasyBar/LocalInstall

PACKAGE_ZIP := $(DIST_DIR)/EasyBar-$(VERSION).zip
CALENDAR_AGENT_PACKAGE_ZIP := $(DIST_DIR)/EasyBarCalendarAgent-$(VERSION).zip
NETWORK_AGENT_PACKAGE_ZIP := $(DIST_DIR)/EasyBarNetworkAgent-$(VERSION).zip

VERSION_PREFIX ?= v
LATEST_TAG := $(shell git tag --list '$(VERSION_PREFIX)*' --sort=-v:refname | head -n 1)
CURRENT_VERSION := $(if $(LATEST_TAG),$(patsubst $(VERSION_PREFIX)%,%,$(LATEST_TAG)),0.0.0)
CURRENT_CORE_VERSION := $(firstword $(subst -, ,$(CURRENT_VERSION)))

NEXT_PATCH := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n}.{p+1}")')
NEXT_MINOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m}.{n+1}.0")')
NEXT_MAJOR := $(shell python3 -c 'm,n,p=map(int,"$(CURRENT_CORE_VERSION)".split(".")); print(f"{m+1}.0.0")')

.DEFAULT_GOAL := help

.PHONY: help build test check check-concurrency check-release-scripts run support \
        bundle package release verify verify-release print-package-sha256 \
        bundle-local install-local uninstall-local stop restart-app print-local-version \
        fmt fmt-swift fmt-md fmt-yaml fmt-json lint lint-swift \
        clean clean-dist \
        tag-patch tag-minor tag-major push-tags tag

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z\_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Build and test

build: ## Build the customizable EasyBar frontend.
	@$(SWIFT) build

test: ## Run EasyBar frontend unit tests.
	@$(SWIFT) test --disable-sandbox

check-concurrency: ## Build with complete strict concurrency checking.
	@$(SWIFT) build -Xswiftc -strict-concurrency=complete

check-release-scripts: ## Test Homebrew cask and agent formula generation.
	@scripts/release/test-homebrew-cask-update.sh

check: test check-concurrency lint check-release-scripts ## Run the complete repository verification suite.

##@ Packaging

bundle: ## Build ad-hoc-signed EasyBar and helper bundles for ARCH.
	@scripts/build/bundle.sh \
		--arch "$(ARCH)" \
		--version "$(VERSION)" \
		--bundle-id "$(BUNDLE_ID)" \
		--dist-dir "$(DIST_DIR)"

package: bundle ## Create EasyBar and helper-agent release ZIPs.
	@scripts/release/package.sh --version "$(VERSION)" --dist-dir "$(DIST_DIR)"

verify: ## Verify the built app, helper bundles, resources, versions, and architectures.
	@scripts/build/verify-bundle.sh --arch "$(ARCH)" --version "$(VERSION)" --dist-dir "$(DIST_DIR)"

verify-release: package ## Build and verify all release ZIPs.
	@scripts/release/verify-release.sh \
		--version "$(VERSION)" \
		--arch "$(ARCH)" \
		--dist-dir "$(DIST_DIR)"

release: verify-release ## Build and verify release artifacts.
	@echo "Release artifacts ready: $(PACKAGE_ZIP) $(CALENDAR_AGENT_PACKAGE_ZIP) $(NETWORK_AGENT_PACKAGE_ZIP)"

print-package-sha256: package ## Print SHA-256 hashes for all release ZIPs.
	@shasum -a 256 "$(PACKAGE_ZIP)" "$(CALENDAR_AGENT_PACKAGE_ZIP)" "$(NETWORK_AGENT_PACKAGE_ZIP)"

##@ Development

support: ## Build and expose EasyBarKit's Lua runtime helper for direct source-tree runs.
	@test -f "$(EASYBAR_KIT_ROOT)/Package.swift" || { echo "EasyBarKit checkout not found: $(EASYBAR_KIT_ROOT)" >&2; exit 1; }
	@$(SWIFT) build --package-path "$(EASYBAR_KIT_ROOT)" --product EasyBarLuaRuntime
	@kit_bin="$$($(SWIFT) build --package-path "$(EASYBAR_KIT_ROOT)" --show-bin-path)"; \
		app_bin="$$($(SWIFT) build --show-bin-path)"; \
		mkdir -p "$$app_bin" .build/debug; \
		ln -sf "$$kit_bin/EasyBarLuaRuntime" "$$app_bin/EasyBarLuaRuntime"; \
		ln -sf "$$kit_bin/EasyBarLuaRuntime" .build/debug/EasyBarLuaRuntime

run: support ## Run EasyBar directly from the source checkout.
	@$(SWIFT) run EasyBar

bundle-local: ## Build a complete local EasyBar.app using the sibling EasyBarKit checkout.
	@local_version="$$(scripts/dev/local-version.sh --version-prefix "$(VERSION_PREFIX)" --dependency-root "$(EASYBAR_KIT_ROOT)")"; \
		echo "Building local EasyBar version $$local_version"; \
		scripts/build/local-bundle.sh \
			--arch "$(LOCAL_INSTALL_ARCH)" \
			--version "$$local_version" \
			--bundle-id "$(BUNDLE_ID)" \
			--dist-dir "$(DIST_DIR)"

install-local: bundle-local ## Build and install EasyBar.app, CLI, Lua runtime, and helper agents locally.
	@scripts/dev/install-local.sh \
		--dist-dir "$(DIST_DIR)" \
		--app-dir "$(LOCAL_APP_DIR)" \
		--bin-dir "$(LOCAL_BIN_DIR)" \
		--agent-dir "$(LOCAL_AGENT_DIR)" \
		--launch-agent-dir "$(LOCAL_LAUNCH_AGENT_DIR)" \
		--log-dir "$(LOCAL_LOG_DIR)" \
		--state-dir "$(LOCAL_STATE_DIR)"

uninstall-local: ## Remove the standalone local EasyBar installation and restore Homebrew agent states.
	@scripts/dev/uninstall-local.sh \
		--app-dir "$(LOCAL_APP_DIR)" \
		--bin-dir "$(LOCAL_BIN_DIR)" \
		--agent-dir "$(LOCAL_AGENT_DIR)" \
		--launch-agent-dir "$(LOCAL_LAUNCH_AGENT_DIR)" \
		--state-dir "$(LOCAL_STATE_DIR)"

stop: ## Stop EasyBar and its locally installed helper agents.
	@scripts/dev/stop-local.sh --dist-dir "$(DIST_DIR)"

restart-app: stop ## Restart the locally installed EasyBar application.
	@open "$(LOCAL_APP_DIR)/EasyBar.app"

print-local-version: ## Print the Git-derived version used by install-local.
	@scripts/dev/local-version.sh --version-prefix "$(VERSION_PREFIX)" --dependency-root "$(EASYBAR_KIT_ROOT)"

##@ Formatting

fmt: fmt-swift fmt-md fmt-yaml fmt-json ## Format supported source files.

fmt-swift: ## Format Swift sources.
	@$(SWIFT) format format --in-place --recursive --parallel Sources Tests

fmt-md: ## Format Markdown files.
	@$(PRETTIER) --write $(PRETTIER_MD_SOURCES)

fmt-yaml: ## Format YAML files.
	@$(PRETTIER) --write $(PRETTIER_YAML_SOURCES)

fmt-json: ## Format JSON files.
	@$(PRETTIER) --write $(PRETTIER_JSON_SOURCES)

lint: lint-swift ## Check formatting without changing files.

lint-swift: ## Check Swift formatting.
	@$(SWIFT) format lint --recursive Sources Tests

##@ Cleanup

clean-dist: ## Remove distribution output.
	@rm -rf "$(DIST_DIR)"

clean: clean-dist ## Remove SwiftPM and distribution output.
	@$(SWIFT) package clean
	@rm -rf .build

##@ Tagging

tag-patch: ## Create the next patch tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_PATCH)" -m "Release $(VERSION_PREFIX)$(NEXT_PATCH)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_PATCH)"

tag-minor: ## Create the next minor tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_MINOR)" -m "Release $(VERSION_PREFIX)$(NEXT_MINOR)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_MINOR)"

tag-major: ## Create the next major tag locally.
	@git tag -a "$(VERSION_PREFIX)$(NEXT_MAJOR)" -m "Release $(VERSION_PREFIX)$(NEXT_MAJOR)"
	@echo "Created tag $(VERSION_PREFIX)$(NEXT_MAJOR)"

push-tags: ## Push commits and tags to origin.
	@git push --follow-tags

tag: ## Show latest tag.
	@echo "Latest version: $(LATEST_TAG)"
