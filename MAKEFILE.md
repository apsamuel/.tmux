# oh-my-tmux — Makefile Reference

> Plugin management and config symlinking via git submodules.

This Makefile manages the tmux configuration lifecycle: symlinking `.tmux.conf`
and `.tmux.conf.local` to `~`, and managing TPM-style plugins as git submodules
under `./plugins/`.

---

## Quick Start

```bash
make                     # print help
make install             # link configs → ~ and sync plugin submodules
make doctor              # read-only health check
```

---

## Parameters

| Parameter       | Effect                                            |
| --------------- | ------------------------------------------------- |
| `PLUGIN`        | `owner/repo` — for `add-plugin` / `remove-plugin` |
| `DOT_DRY_RUN=1` | Preview all actions, no mutations                 |
| `DOT_DEBUG=1`   | Enable bash xtrace for debugging                  |
| `DOT_VERBOSE=1` | Verbose git submodule output                      |

---

## Targets

| Target          | Description                                          |
| --------------- | ---------------------------------------------------- |
| `help`          | Show all targets with descriptions                   |
| `install`       | Symlink configs to `~` + init/sync plugin submodules |
| `clean`         | Remove tmux config symlinks from `~`                 |
| `update`        | Pull latest for all declared plugin submodules       |
| `status`        | Show symlink health and plugin installation status   |
| `add-plugin`    | Declare + clone a new plugin (`PLUGIN=owner/repo`)   |
| `remove-plugin` | Undeclare + remove a plugin (`PLUGIN=owner/repo`)    |
| `sync-plugins`  | Reconcile declared plugins ↔ on-disk submodules      |
| `list-plugins`  | Show declared vs installed plugin status             |
| `doctor`        | Read-only health check (tmux, symlinks, plugins)     |

---

## Examples

```bash
# Install/update from scratch
make install

# Preview what install would do
DOT_DRY_RUN=1 make install

# Add a plugin
make add-plugin PLUGIN=tmux-plugins/tmux-resurrect

# Remove a plugin
make remove-plugin PLUGIN=tmux-plugins/tmux-resurrect

# Check health
make doctor

# Debug a failing target
DOT_DEBUG=1 make install
```

---

## Root Makefile Integration

The parent `dot` Makefile provides passthrough targets with automatic flag
propagation:

```bash
# These are equivalent:
make tmux-install                           # from ~/.dot
cd vendor/oh-my-tmux && make install        # directly

# Dry-run propagates automatically:
DRY=1 make tmux-install                     # from ~/.dot
```

Available root passthroughs: `tmux-install`, `tmux-clean`, `tmux-update`,
`tmux-status`, `tmux-add-plugin`, `tmux-remove-plugin`, `tmux-sync-plugins`,
`tmux-list-plugins`, `tmux-doctor`.
