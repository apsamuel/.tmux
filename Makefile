# ──────────────────────────────────────────────────────────────────────────────
# oh-my-tmux — symlink configs, manage plugins as git submodules
#
# Plugins live under ./plugins/ as git submodules. The source of truth for
# which plugins are enabled is .tmux.conf.local (set -g @plugin 'owner/repo').
# Runtime keybindings (prefix + I/u/M-u/M-l) invoke lib/tmux-helpers.sh.
#
# Usage:
#   make                                     # print help
#   make install                             # link configs → ~ + sync plugins
#   make update                              # pull latest for declared plugins
#   make clean                               # remove config symlinks from ~
#   make status                              # symlink health + plugin status
#   make add-plugin PLUGIN=owner/repo        # declare + clone a new plugin
#   make remove-plugin PLUGIN=owner/repo     # undeclare + remove a plugin
#   make sync-plugins                        # reconcile declared ↔ on-disk
#   make list-plugins                        # show declared vs installed
#
# Parameters:
#   PLUGIN    owner/repo (for add-plugin / remove-plugin)
#   DOT_DRY_RUN=1  print planned changes, do not mutate
#   DOT_DEBUG=1    enable bash xtrace (-x)
#   DOT_VERBOSE=1  verbose helper output
#
# Lives inside vendor/oh-my-tmux (submodule). Called directly or via top-level
# dot Makefile passthrough targets (make tmux-install, tmux-add-plugin, …).
# ──────────────────────────────────────────────────────────────────────────────

SHELL := /bin/bash
.SHELLFLAGS := -eu -o pipefail -c
.DEFAULT_GOAL := help

# ── Layout ────────────────────────────────────────────────────────────────────
REPO       := $(shell cd "$(dir $(lastword $(MAKEFILE_LIST)))" && pwd)
HELPERS    := $(REPO)/lib/tmux-helpers.sh
CONF_LOCAL := $(REPO)/.tmux.conf.local

# ── Parameters ────────────────────────────────────────────────────────────────
PLUGIN      ?=
DRY         ?= 0
DEBUG       ?= 0
VERBOSE     ?= 0
DOT_DRY_RUN ?= $(DRY)
DOT_DEBUG   ?= $(DEBUG)
DOT_VERBOSE ?= $(VERBOSE)

RECIPE_ENV := set -euo pipefail; \
	if [[ "$(DOT_DEBUG)" == "1" ]]; then set -x; fi; \
	dry="$(DOT_DRY_RUN)"

# ── Guards ────────────────────────────────────────────────────────────────────
define require_plugin
	@if [[ -z "$(PLUGIN)" ]]; then echo "ERROR: PLUGIN is required (e.g., PLUGIN=tmux-plugins/tmux-yank)" >&2; exit 1; fi
endef

# ── Phony declarations ───────────────────────────────────────────────────────
.PHONY: help install clean update status doctor \
        add-plugin remove-plugin sync-plugins list-plugins

# ══════════════════════════════════════════════════════════════════════════════
# Help
# ══════════════════════════════════════════════════════════════════════════════

help: ## Show this help
	@echo "oh-my-tmux — plugin management via git submodules"
	@echo ""
	@echo "Usage:  make <target> [PARAMS]"
	@echo ""
	@echo "Parameters:"
	@echo "  PLUGIN=owner/repo   for add-plugin / remove-plugin"
	@echo "  DOT_DRY_RUN=1       preview only, no mutations"
	@echo "  DOT_DEBUG=1         enable xtrace"
	@echo "  DOT_VERBOSE=1       verbose helper output"
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ══════════════════════════════════════════════════════════════════════════════
# Targets
# ══════════════════════════════════════════════════════════════════════════════

install: ## Link configs → ~ and sync plugin submodules
	@$(RECIPE_ENV); \
	echo "[install] linking .tmux.conf → ~/.tmux.conf"; \
	if [[ "$$dry" == "1" ]]; then \
		echo "[dry-run] ln -sfn $(REPO)/.tmux.conf $(HOME)/.tmux.conf"; \
	else \
		ln -sfn "$(REPO)/.tmux.conf" "$(HOME)/.tmux.conf"; \
	fi; \
	echo "[install] linking .tmux.conf.local → ~/.tmux.conf.local"; \
	if [[ "$$dry" == "1" ]]; then \
		echo "[dry-run] ln -sfn $(REPO)/.tmux.conf.local $(HOME)/.tmux.conf.local"; \
	else \
		ln -sfn "$(REPO)/.tmux.conf.local" "$(HOME)/.tmux.conf.local"; \
	fi; \
	if [ -e "$(HOME)/.tmux" ] || [ -L "$(HOME)/.tmux" ]; then \
		echo "[install] archiving legacy ~/.tmux → ~/.tmux.bak"; \
		if [[ "$$dry" == "1" ]]; then \
			echo "[dry-run] rm -rf $(HOME)/.tmux.bak"; \
			echo "[dry-run] mv $(HOME)/.tmux $(HOME)/.tmux.bak"; \
		else \
			rm -rf "$(HOME)/.tmux.bak"; \
			mv "$(HOME)/.tmux" "$(HOME)/.tmux.bak"; \
		fi; \
	fi; \
	echo "[install] syncing plugin submodules..."; \
	DOT_DRY_RUN="$(DOT_DRY_RUN)" DOT_DEBUG="$(DOT_DEBUG)" DOT_VERBOSE="$(DOT_VERBOSE)" "$(HELPERS)" install_plugin sync; \
	echo "[install] done"

clean: ## Remove tmux config symlinks from ~
	@$(RECIPE_ENV); \
	echo "[clean] removing tmux config symlinks"; \
	if [[ "$$dry" == "1" ]]; then \
		echo "[dry-run] rm -f $(HOME)/.tmux.conf $(HOME)/.tmux.conf.local"; \
	else \
		rm -f "$(HOME)/.tmux.conf" "$(HOME)/.tmux.conf.local"; \
	fi; \
	echo "[clean] done"

update: ## Pull latest for all declared plugin submodules
	@echo "[update] updating plugin submodules"
	@DOT_DRY_RUN="$(DOT_DRY_RUN)" DOT_DEBUG="$(DOT_DEBUG)" DOT_VERBOSE="$(DOT_VERBOSE)" "$(HELPERS)" install_plugin update
	@echo "[update] done"

status: ## Show symlink health and plugin status
	@echo "── tmux config symlinks ──"
	@for f in .tmux.conf .tmux.conf.local; do \
		if [ -L "$(HOME)/$$f" ]; then \
			printf '  ✔  ~/%-20s → %s\n' "$$f" "$$(readlink "$(HOME)/$$f")"; \
		elif [ -e "$(HOME)/$$f" ]; then \
			printf '  ✘  ~/%-20s exists but is NOT a symlink\n' "$$f"; \
		else \
			printf '  ✘  ~/%-20s missing\n' "$$f"; \
		fi; \
	done
	@echo ""
	@echo "── plugin submodules ──"
	@DOT_DRY_RUN="$(DOT_DRY_RUN)" DOT_DEBUG="$(DOT_DEBUG)" DOT_VERBOSE="$(DOT_VERBOSE)" "$(HELPERS)" install_plugin list

add-plugin: ## Declare + clone a plugin (PLUGIN=owner/repo)
	$(require_plugin)
	@$(RECIPE_ENV); \
	echo "[add-plugin] $(PLUGIN)"; \
	if grep -qE "^set -g @plugin '$(PLUGIN)'" "$(CONF_LOCAL)" 2>/dev/null; then \
		echo "  ✓ Already declared in .tmux.conf.local"; \
	else \
		echo "  Adding declaration to .tmux.conf.local..."; \
		if [[ "$$dry" == "1" ]]; then \
			echo "[dry-run] printf '\\nset -g @plugin '\''$(PLUGIN)'\''\\n' >> $(CONF_LOCAL)"; \
		else \
			printf '\nset -g @plugin '\''$(PLUGIN)'\''\n' >> "$(CONF_LOCAL)"; \
		fi; \
	fi
	@$(RECIPE_ENV); \
	NAME=$$(basename "$(PLUGIN)" .git); \
	if [ -d "$(REPO)/plugins/$$NAME" ]; then \
		echo "  ✓ Submodule already exists: plugins/$$NAME"; \
	else \
		echo "  Registering submodule..."; \
		if [[ "$$dry" == "1" ]]; then \
			echo "[dry-run] git -C $(REPO) submodule add git@github.com:$(PLUGIN).git plugins/$$NAME"; \
		else \
			git -C "$(REPO)" submodule add "git@github.com:$(PLUGIN).git" "plugins/$$NAME"; \
		fi; \
	fi
	@$(RECIPE_ENV); \
	NAME=$$(basename "$(PLUGIN)" .git); \
	echo "  Initializing submodule..."; \
	if [[ "$$dry" == "1" ]]; then \
		echo "[dry-run] git -C $(REPO) submodule update --init plugins/$$NAME"; \
	else \
		git -C "$(REPO)" submodule update --init "plugins/$$NAME"; \
	fi
	@echo "[add-plugin] done"

remove-plugin: ## Undeclare + remove a plugin (PLUGIN=owner/repo)
	$(require_plugin)
	@$(RECIPE_ENV); \
	echo "[remove-plugin] $(PLUGIN)"; \
	if grep -qE "^set -g @plugin '$(PLUGIN)'" "$(CONF_LOCAL)" 2>/dev/null; then \
		echo "  Removing declaration from .tmux.conf.local..."; \
		if [[ "$$dry" == "1" ]]; then \
			echo "[dry-run] sed -i '' '/^set -g @plugin '$(subst /,\/,$(PLUGIN))'/d' $(CONF_LOCAL)"; \
		else \
			sed -i '' "/^set -g @plugin '$(subst /,\/,$(PLUGIN))'/d" "$(CONF_LOCAL)"; \
		fi; \
	else \
		echo "  ✓ Not declared in .tmux.conf.local"; \
	fi
	@$(RECIPE_ENV); \
	NAME=$$(basename "$(PLUGIN)" .git); \
	if git -C "$(REPO)" config -f .gitmodules --get "submodule.plugins/$$NAME.url" >/dev/null 2>&1; then \
		echo "  Removing submodule..."; \
		if [[ "$$dry" == "1" ]]; then \
			echo "[dry-run] git -C $(REPO) submodule deinit -f plugins/$$NAME"; \
			echo "[dry-run] git -C $(REPO) rm -f plugins/$$NAME"; \
			echo "[dry-run] rm -rf $(REPO)/.git/modules/plugins/$$NAME"; \
		else \
			git -C "$(REPO)" submodule deinit -f "plugins/$$NAME" 2>/dev/null || true; \
			git -C "$(REPO)" rm -f "plugins/$$NAME" 2>/dev/null || true; \
			rm -rf "$(REPO)/.git/modules/plugins/$$NAME"; \
		fi; \
	else \
		echo "  ✓ Submodule not registered in .gitmodules"; \
	fi
	@echo "[remove-plugin] done"

sync-plugins: ## Reconcile declared plugins ↔ on-disk submodules
	@echo "[sync-plugins] reconciling..."
	@DOT_DRY_RUN="$(DOT_DRY_RUN)" DOT_DEBUG="$(DOT_DEBUG)" DOT_VERBOSE="$(DOT_VERBOSE)" "$(HELPERS)" install_plugin sync
	@echo "[sync-plugins] done"

list-plugins: ## Show declared vs installed plugin status
	@DOT_DRY_RUN="$(DOT_DRY_RUN)" DOT_DEBUG="$(DOT_DEBUG)" DOT_VERBOSE="$(DOT_VERBOSE)" "$(HELPERS)" install_plugin list


# ══════════════════════════════════════════════════════════════════════════════
# Doctor — read-only health check
# ══════════════════════════════════════════════════════════════════════════════

doctor: ## Read-only health check (tmux, symlinks, plugins)
	@$(RECIPE_ENV); \
	fails=0; \
	echo "── oh-my-tmux doctor ──"; \
	echo ""; \
	echo "── dependencies ──"; \
	if command -v tmux >/dev/null 2>&1; then \
		printf '  ✔  tmux %s\n' "$$(tmux -V 2>/dev/null | head -1)"; \
	else \
		printf '  ✘  tmux not found\n'; \
		fails=$$((fails + 1)); \
	fi; \
	echo ""; \
	echo "── config symlinks ──"; \
	for f in .tmux.conf .tmux.conf.local; do \
		if [ -L "$(HOME)/$$f" ]; then \
			target=$$(readlink "$(HOME)/$$f"); \
			case "$$f" in \
				.tmux.conf)       expected="$(REPO)/.tmux.conf" ;; \
				.tmux.conf.local) expected="$(CONF_LOCAL)" ;; \
			esac; \
			if [ "$$target" = "$$expected" ]; then \
				printf '  ✔  ~/%-20s → %s\n' "$$f" "$$target"; \
			else \
				printf '  ✘  ~/%-20s → %s (expected %s)\n' "$$f" "$$target" "$$expected"; \
				fails=$$((fails + 1)); \
			fi; \
		elif [ -e "$(HOME)/$$f" ]; then \
			printf '  ✘  ~/%-20s exists but is NOT a symlink\n' "$$f"; \
			fails=$$((fails + 1)); \
		else \
			printf '  ✘  ~/%-20s missing\n' "$$f"; \
			fails=$$((fails + 1)); \
		fi; \
	done; \
	echo ""; \
	echo "── plugin submodules ──"; \
	if [ -r "$(CONF_LOCAL)" ]; then \
		while IFS= read -r line; do \
			plugin=$$(echo "$$line" | sed "s/^set -g @plugin '\(.*\)'/\1/"); \
			name=$$(basename "$$plugin"); \
			if [ -d "$(REPO)/plugins/$$name" ] && [ -n "$$(ls -A "$(REPO)/plugins/$$name" 2>/dev/null)" ]; then \
				printf '  ✔  %-30s ok\n' "$$plugin"; \
			elif [ -d "$(REPO)/plugins/$$name" ]; then \
				printf '  ✘  %-30s directory exists but empty (not checked out)\n' "$$plugin"; \
				fails=$$((fails + 1)); \
			else \
				printf '  ✘  %-30s directory missing\n' "$$plugin"; \
				fails=$$((fails + 1)); \
			fi; \
		done < <(grep -E "^set -g @plugin '" "$(CONF_LOCAL)"); \
	else \
		printf '  ✘  %s not found\n' "$(CONF_LOCAL)"; \
		fails=$$((fails + 1)); \
	fi; \
	echo ""; \
	if [ $$fails -gt 0 ]; then \
		echo "✘ $$fails issue(s) found"; \
		exit 1; \
	else \
		echo "✔ oh-my-tmux fully healthy"; \
	fi
