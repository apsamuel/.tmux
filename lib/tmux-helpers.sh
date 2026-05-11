#!/usr/bin/env sh
# tmux-helpers.sh — shell helpers invoked from tmux via run-shell / if-shell
#
# Usage from .tmux.conf.local:
#   bind-key H run-shell '"$TMUX_HELPERS" hello'
#   bind-key I run-shell '"$TMUX_HELPERS" install_plugin install'
#
# Each invocation is a fresh process. Keep functions small.
# Dispatch: first arg = function name; remaining args passed through.

set -eu

DOT_DRY_RUN="${DOT_DRY_RUN:-0}"
DOT_DEBUG="${DOT_DEBUG:-0}"
DOT_VERBOSE="${DOT_VERBOSE:-0}"

if [ "${DOT_DEBUG}" = "1" ]; then
    set -x
fi

is_dry() {
    [ "${DOT_DRY_RUN}" = "1" ]
}

run_mutation() {
    if is_dry; then
        printf '[dry-run] %s\n' "$*"
        return 0
    fi
    "$@"
}

# ── core helpers ─────────────────────────────────────────────────────────────

_log() {
    log_dir="${XDG_STATE_HOME:-$HOME/.local/state}/tmux"
    mkdir -p "$log_dir"
    printf '%s  %s\n' "$(date '+%Y-%m-%d %H:%M:%S')" "$*" >> "$log_dir/helpers.log"
}

# notify both via tmux display-message and stdout (when run from CLI)
_notify() {
    if [ -n "${TMUX:-}" ] && ! is_dry; then
        tmux display-message "$*"
    fi
    printf '%s\n' "$*"
}

# resolve oh-my-tmux repo root (this script lives in <root>/lib/)
_omt_root() {
    script_dir=$(CDPATH='' cd -- "$(dirname -- "$0")" && pwd)
    CDPATH='' cd -- "$script_dir/.." && pwd
}

# ── hello (smoke test) ───────────────────────────────────────────────────────

hello() {
    session=$(tmux display-message -p '#S' 2>/dev/null || echo '?')
    pane=$(tmux display-message -p '#{pane_id}' 2>/dev/null || echo '?')
    stamp=$(date '+%H:%M:%S')
    _log "hello session=${session} pane=${pane}"
    tmux display-message "👋 hello from ${session} (${pane}) @ ${stamp}"
}

# ── plugin manager ───────────────────────────────────────────────────────────
#
# Plugins live as git submodules under <oh-my-tmux>/plugins/<name>.
# Declarations are read from the compiled tmux config: starting from
# ~/.tmux.conf, all `source-file`/`source` directives are followed
# recursively, and every `set -g @plugin '<owner/repo>'` line is collected.
#
# Subcommands:
#   install_plugin add <owner/repo|url> [name]   — add new plugin (submodule)
#   install_plugin install                       — clone any declared, missing
#   install_plugin update                        — pull latest for declared
#   install_plugin clean                         — remove on-disk, undeclared
#   install_plugin sync                          — install + clean
#   install_plugin list                          — show declared / installed
#
# Backwards compat: `install_plugin owner/repo` still works and is treated
# as `install_plugin add owner/repo`.

# expand $VAR / ${VAR} / ~ in a path string
_expand_path() {
    p="$1"
    case "$p" in
        \~/*) p="$HOME/${p#~/}" ;;
        \~)   p="$HOME" ;;
    esac
    # expand environment variables
    eval "printf '%s' \"$p\""
}

# echo declared plugins (one "owner/repo" per line) by walking config sources
_plugin_scan_file() {
    f="$1"
    [ -r "$f" ] || return 0
    # extract @plugin '...' / "..." values
    awk '
        /^[[:space:]]*set(-option)?[[:space:]]+(-[gqu][[:space:]]+)*@plugin[[:space:]]/ {
            line = $0
            if (match(line, /'\''[^'\'']+'\''/)) {
                print substr(line, RSTART+1, RLENGTH-2)
            } else if (match(line, /"[^"]+"/)) {
                print substr(line, RSTART+1, RLENGTH-2)
            }
        }
    ' "$f"
    # follow source / source-file directives
    awk '
        /^[[:space:]]*source(-file)?[[:space:]]/ {
            sub(/^[[:space:]]*source(-file)?[[:space:]]+/, "", $0)
            sub(/[[:space:]]*#.*$/, "", $0)
            sub(/^['\''"]/, "", $0); sub(/['\''"][[:space:]]*$/, "", $0)
            print $0
        }
    ' "$f" | while IFS= read -r raw; do
        [ -n "$raw" ] || continue
        nested=$(_expand_path "$raw")
        case "$nested" in
            /*) ;;
            *) nested="$(dirname -- "$f")/$nested" ;;
        esac
        _plugin_scan_file "$nested"
    done
}

_plugin_declared() {
    # oh-my-tmux exports TMUX_CONF and TMUX_CONF_LOCAL into the env via
    # set-environment -g; pull them from a running tmux when available.
    conf="${TMUX_CONF:-$HOME/.tmux.conf}"
    local_conf="${TMUX_CONF_LOCAL:-$HOME/.tmux.conf.local}"
    if [ -n "${TMUX:-}" ]; then
        c=$(tmux show-environment -g TMUX_CONF 2>/dev/null | sed -n 's/^TMUX_CONF=//p')
        l=$(tmux show-environment -g TMUX_CONF_LOCAL 2>/dev/null | sed -n 's/^TMUX_CONF_LOCAL=//p')
        [ -n "$c" ] && conf="$c"
        [ -n "$l" ] && local_conf="$l"
    fi
    {
        _plugin_scan_file "$conf"
        [ "$local_conf" != "$conf" ] && _plugin_scan_file "$local_conf"
    } | awk 'NF && !seen[$0]++'
}

# echo installed plugin directory names (under plugins/, excluding tpm)
_plugin_installed() {
    root=$(_omt_root)
    [ -d "$root/plugins" ] || return 0
    for d in "$root"/plugins/*/; do
        [ -d "$d" ] || continue
        name=$(basename "$d")
        [ "$name" = "tpm" ] && continue
        printf '%s\n' "$name"
    done
}

# convert a declared spec (owner/repo or full url) to an SSH github url
_plugin_url() {
    spec="$1"
    case "$spec" in
        *://*|git@*) printf '%s' "$spec" ;;
        */*)         printf 'git@github.com:%s.git' "$spec" ;;
        *)           return 1 ;;
    esac
}

# extract dir name from a spec
_plugin_name() {
    spec="$1"
    case "$spec" in
        *://*|git@*) basename "$spec" .git ;;
        */*)         printf '%s\n' "${spec##*/}" ;;
        *)           return 1 ;;
    esac
}

# add a plugin as a submodule
_plugin_add() {
    spec="$1"
    name="${2:-$(_plugin_name "$spec")}"
    url=$(_plugin_url "$spec") || {
        echo "install_plugin: '$spec' is not owner/repo or a git URL" >&2
        return 2
    }
    root=$(_omt_root)
    target="plugins/$name"

    if [ -e "$root/$target" ]; then
        echo "install_plugin: $target already exists" >&2
        return 1
    fi

    run_mutation sh -c "cd \"$root\" && git submodule add \"$url\" \"$target\"" || return $?
    _log "plugin add name=$name url=$url"
    if is_dry; then
        _notify "[dry-run] would add $target ($url)"
    else
        _notify "✅ added $target ($url)"
    fi
    cat <<EOF

next steps:
  1. declare in ~/.tmux.conf.local under "tpm plugins":
       set -g @plugin '$(printf '%s' "$url" | sed -E 's#.*[:/]([^/]+/[^/]+)\.git$#\1#')'
  2. commit inside oh-my-tmux:
       (cd "$root" && git commit -m "add $name plugin" .gitmodules "$target")
  3. bump pointer in parent repo:
       git -C "\$HOME/.dot" commit -m "bump oh-my-tmux: add $name" vendor/oh-my-tmux
EOF
}

# install (clone) every declared plugin not yet on disk
_plugin_install_missing() {
    root=$(_omt_root)
    count=0
    _plugin_declared | while IFS= read -r spec; do
        name=$(_plugin_name "$spec") || continue
        [ "$name" = "tpm" ] && continue
        if [ -d "$root/plugins/$name" ]; then
            continue
        fi
        url=$(_plugin_url "$spec") || continue
        echo "→ adding $name ($url)"
        run_mutation sh -c "cd \"$root\" && git submodule add \"$url\" \"plugins/$name\"" \
            && _log "plugin install name=$name url=$url" \
            && count=$((count + 1)) || echo "  failed: $name"
    done
    _notify "tmux plugins: install pass complete"
}

# update declared plugins to their tip (per-submodule remote update)
_plugin_update_all() {
    root=$(_omt_root)
    _plugin_declared | while IFS= read -r spec; do
        name=$(_plugin_name "$spec") || continue
        [ "$name" = "tpm" ] && continue
        [ -d "$root/plugins/$name/.git" ] || [ -f "$root/plugins/$name/.git" ] || {
            echo "skip $name (not installed)"
            continue
        }
        echo "→ updating $name"
        run_mutation sh -c "cd \"$root\" && git submodule update --remote --merge -- \"plugins/$name\"" \
            || echo "  failed: $name"
        _log "plugin update name=$name"
    done
    _notify "tmux plugins: update pass complete"
}

# remove on-disk plugins not declared in config
_plugin_clean_orphans() {
    root=$(_omt_root)
    declared=$(_plugin_declared | while IFS= read -r s; do _plugin_name "$s"; done)
    _plugin_installed | while IFS= read -r name; do
        if printf '%s\n' "$declared" | grep -qx "$name"; then
            continue
        fi
        echo "→ removing orphan $name"
                if is_dry; then
                        printf '[dry-run] git -C %s submodule deinit -f -- plugins/%s\n' "$root" "$name"
                        printf '[dry-run] git -C %s rm -f plugins/%s\n' "$root" "$name"
                        printf '[dry-run] rm -rf %s/.git/modules/plugins/%s\n' "$root" "$name"
                else
                        ( cd "$root" \
                                && git submodule deinit -f -- "plugins/$name" >/dev/null 2>&1 || true
                            cd "$root" \
                                && git rm -f "plugins/$name" >/dev/null 2>&1 \
                                || rm -rf "plugins/$name"
                            rm -rf "$root/.git/modules/plugins/$name"
                        )
                fi
        _log "plugin clean name=$name"
    done
    _notify "tmux plugins: clean pass complete"
}

# show status table
_plugin_list() {
    root=$(_omt_root)
    declared=$(_plugin_declared)
    installed=$(_plugin_installed)

    printf 'declared (from compiled tmux config):\n'
    if [ -z "$declared" ]; then
        printf '  (none)\n'
    else
        printf '%s\n' "$declared" | while IFS= read -r spec; do
            name=$(_plugin_name "$spec")
            if printf '%s\n' "$installed" | grep -qx "$name"; then
                printf '  ✓ %-32s %s\n' "$name" "$spec"
            else
                printf '  ✗ %-32s %s   (missing)\n' "$name" "$spec"
            fi
        done
    fi

    orphans=""
    declared_names=$(printf '%s\n' "$declared" | while IFS= read -r s; do
        [ -n "$s" ] && _plugin_name "$s"
    done)
    for name in $installed; do
        if ! printf '%s\n' "$declared_names" | grep -qx "$name"; then
            orphans="${orphans}${name}
"
        fi
    done
    if [ -n "$orphans" ]; then
        printf '\norphans (on disk, not declared):\n'
        printf '%s' "$orphans" | sed '/^$/d; s/^/  ! /'
    fi
}

install_plugin() {
    sub="${1:-list}"
    case "$sub" in
        add)
            shift
            [ "$#" -ge 1 ] || { echo "usage: install_plugin add <owner/repo|url> [name]" >&2; return 2; }
            _plugin_add "$@"
            ;;
        install)  _plugin_install_missing ;;
        update)   _plugin_update_all ;;
        clean)    _plugin_clean_orphans ;;
        sync)     _plugin_install_missing && _plugin_clean_orphans ;;
        list|ls|"") _plugin_list ;;
        # backwards compat: bare owner/repo or url means `add`
        *)
            case "$sub" in
                *://*|git@*|*/*) _plugin_add "$@" ;;
                *)
                    echo "install_plugin: unknown subcommand '$sub'" >&2
                    echo "  try: add | install | update | clean | sync | list" >&2
                    return 2
                    ;;
            esac
            ;;
    esac
}

# ── dispatch ─────────────────────────────────────────────────────────────────

if [ "$#" -eq 0 ]; then
    grep -E '^[a-zA-Z][a-zA-Z0-9_-]*\(\)' "$0" | sed 's/().*//' | grep -v '^_' | sort
    exit 0
fi

cmd="$1"
shift
if ! type "$cmd" >/dev/null 2>&1; then
    echo "tmux-helpers: unknown command '${cmd}'" >&2
    exit 1
fi
"$cmd" "$@"
