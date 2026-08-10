EASYBAR_KIT_ROOT ?= ../easybar-kit
SWIFT ?= swift
INSTALL ?= install
PRETTIER ?= npx --yes prettier@3.9.6
PRETTIER_MD_SOURCES := README.md
PRETTIER_YAML_SOURCES := ".github/**/*.{yml,yaml}"
PRETTIER_JSON_SOURCES := ".github/**/*.json"
LOCAL_BIN_DIR ?= $(HOME)/.local/bin

.DEFAULT_GOAL := help

.PHONY: help build test check check-concurrency run support install-local \
        fmt fmt-swift fmt-md fmt-yaml fmt-json \
        lint lint-swift clean

help: ## Display this help.
	@awk 'BEGIN {FS = ":.*##"; printf "\nUsage:\n  make \033[36m<target>\033[0m\n"} /^[a-zA-Z\_0-9-]+:.*?##/ { printf "  \033[36m%-20s\033[0m %s\n", $$1, $$2 } /^##@/ { printf "\n\033[1m%s\033[0m\n", substr($$0, 5) }' $(MAKEFILE_LIST)

##@ Build and test

build: ## Build the customizable EasyBar frontend.
	@$(SWIFT) build

check: test check-concurrency lint ## Run the complete repository verification suite.

test: ## Run EasyBar frontend unit tests.
	@$(SWIFT) test --disable-sandbox

check-concurrency: ## Build with complete strict concurrency checking.
	@$(SWIFT) build -Xswiftc -strict-concurrency=complete

##@ Development

support: ## Build and expose the shared Lua runtime helper for source-tree runs.
	@$(SWIFT) build --package-path "$(EASYBAR_KIT_ROOT)" --product EasyBarLuaRuntime
	@kit_bin="$$($(SWIFT) build --package-path "$(EASYBAR_KIT_ROOT)" --show-bin-path)"; \
		app_bin="$$($(SWIFT) build --show-bin-path)"; \
		mkdir -p "$$app_bin" .build/debug; \
		ln -sf "$$kit_bin/EasyBarLuaRuntime" "$$app_bin/EasyBarLuaRuntime"; \
		ln -sf "$$kit_bin/EasyBarLuaRuntime" .build/debug/EasyBarLuaRuntime

run: support ## Run EasyBar from the source checkout.
	@$(SWIFT) run EasyBar

install-local: ## Install EasyBar and its shared support executables into LOCAL_BIN_DIR.
	@$(MAKE) -C "$(EASYBAR_KIT_ROOT)" install-local LOCAL_BIN_DIR="$(LOCAL_BIN_DIR)"
	@$(SWIFT) build -c release
	@$(INSTALL) -d "$(LOCAL_BIN_DIR)"
	@bin_dir="$$($(SWIFT) build -c release --show-bin-path)"; \
		$(INSTALL) -m 755 "$$bin_dir/EasyBar" "$(LOCAL_BIN_DIR)/EasyBar"

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

clean: ## Remove SwiftPM build output.
	@$(SWIFT) package clean
	@rm -rf .build
