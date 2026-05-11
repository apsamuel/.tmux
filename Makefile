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
PLUGIN ?=

# ── Guards ────────────────────────────────────────────────────────────────────
define require_plugin
	@if [[ -z "$(PLUGIN)" ]]; then echo "ERROR: PLUGIN is required (e.g., PLUGIN=tmux-plugins/tmux-yank)" >&2; exit 1; fi
endef

# ── Phony declarations ───────────────────────────────────────────────────────
.PHONY: help install clean update status \
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
	@echo ""
	@echo "Targets:"
	@grep -E '^[a-zA-Z0-9_-]+:.*?## .*$$' $(MAKEFILE_LIST) | \
		awk 'BEGIN {FS = ":.*?## "}; {printf "  \033[36m%-16s\033[0m %s\n", $$1, $$2}'

# ══════════════════════════════════════════════════════════════════════════════
# Targets
# ══════════════════════════════════════════════════════════════════════════════

install: ## Link configs → ~ and sync plugin submodules
	@echo "[install] linking .tmux.conf → ~/.tmux.conf"
	@ln -sfn "$(REPO)/.tmux.conf" "$(HOME)/.tmux.conf"
	@echo "[install] linking .tmux.conf.local → ~/.tmux.conf.local"
	@ln -sfn "$(REPO)/.tmux.conf.local" "$(HOME)/.tmux.conf.local"
	@# archive legacy ~/.tmux if it exists
	@if [ -e "$(HOME)/.tmux" ] || [ -L "$(HOME)/.tmux" ]; then \
		echo "[install] archiving legacy ~/.tmux → ~/.tmux.bak"; \
		rm -rf "$(HOME)/.tmux.bak"; \
		mv "$(HOME)/.tmux" "$(HOME)/.tmux.bak"; \
	fi
	@echo "[install] syncing plugin submodules..."
	@"$(HELPERS)" install_plugin sync
	@echo "[install] done"

clean: ## Remove tmux config symlinks from ~
	@echo "[clean] removing tmux config symlinks"
	@rm -f "$(HOME)/.tmux.conf" "$(HOME)/.tmux.conf.local"
	@echo "[clean] done"

update: ## Pull latest for all declared plugin submodules
	@echo "[update] updating plugin submodules"
	@"$(HELPERS)" install_plugin update
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
	@"$(HELPERS)" install_plugin list

add-plugin: ## Declare + clone a plugin (PLUGIN=owner/repo)
	$(require_plugin)
	@echo "[add-plugin] $(PLUGIN)"
	@if grep -qE "^set -g @plugin '$(PLUGIN)'" "$(CONF_LOCAL)" 2>/dev/null; then \
		echo "  ✓ Already declared in .tmux.conf.local"; \
	else \
		echo "  Adding declaration to .tmux.conf.local..."; \
		printf '\nset -g @plugin '\''$(PLUGIN)'\''\n' >> "$(CONF_LOCAL)"; \
	fi
	@NAME=$$(basename "$(PLUGIN)" .git); \
	if [ -d "$(REPO)/plugins/$$NAME" ]; then \
		echo "  ✓ Submodule already exists: plugins/$$NAME"; \
	else \
		echo "  Registering submodule..."; \
		git -C "$(REPO)" submodule add "git@github.com:$(PLUGIN).git" "plugins/$$NAME"; \
	fi
	@NAME=$$(basename "$(PLUGIN)" .git); \
	echo "  Initializing submodule..."; \
	git -C "$(REPO)" submodule update --init "plugins/$$NAME"
	@echo "[add-plugin] done"

remove-plugin: ## Undeclare + remove a plugin (PLUGIN=owner/repo)
	$(require_plugin)
	@echo "[remove-plugin] $(PLUGIN)"
	@if grep -qE "^set -g @plugin '$(PLUGIN)'" "$(CONF_LOCAL)" 2>/dev/null; then \
		echo "  Removing declaration from .tmux.conf.local..."; \
		sed -i '' "/^set -g @plugin '$(subst /,\/,$(PLUGIN))'/d" "$(CONF_LOCAL)"; \
	else \
		echo "  ✓ Not declared in .tmux.conf.local"; \
	fi
	@NAME=$$(basename "$(PLUGIN)" .git); \
	if git -C "$(REPO)" config -f .gitmodules --get "submodule.plugins/$$NAME.url" >/dev/null 2>&1; then \
		echo "  Removing submodule..."; \
		git -C "$(REPO)" submodule deinit -f "plugins/$$NAME" 2>/dev/null || true; \
		git -C "$(REPO)" rm -f "plugins/$$NAME" 2>/dev/null || true; \
		rm -rf "$(REPO)/.git/modules/plugins/$$NAME"; \
	else \
		echo "  ✓ Submodule not registered in .gitmodules"; \
	fi
	@echo "[remove-plugin] done"

sync-plugins: ## Reconcile declared plugins ↔ on-disk submodules
	@echo "[sync-plugins] reconciling..."
	@"$(HELPERS)" install_plugin sync
	@echo "[sync-plugins] done"

list-plugins: ## Show declared vs installed plugin status
	@"$(HELPERS)" install_plugin list
