#!/usr/bin/env sh
# tmux-bindings.sh — apply our keybindings AFTER tmux finishes its own
# config load (oh-my-tmux's _apply_bindings + tpm). Invoked as:
#   run-shell -b 'sh "$HOME/.dot/vendor/oh-my-tmux/lib/tmux-bindings.sh"'
# from .tmux.conf.local.

set -eu
sleep 0.5

H="${TMUX_HELPERS:-$HOME/.dot/vendor/oh-my-tmux/lib/tmux-helpers.sh}"

tmux bind-key H   run-shell "\"$H\" hello"
tmux bind-key I   run-shell "\"$H\" install_plugin install ; tmux display-message 'plugins: install pass complete'"
tmux bind-key u   run-shell "\"$H\" install_plugin update  ; tmux display-message 'plugins: update pass complete'"
tmux bind-key M-u run-shell "\"$H\" install_plugin clean   ; tmux display-message 'plugins: clean pass complete'"
tmux bind-key M-l display-popup -E -w 80% -h 70% \
    "\"$H\" install_plugin list ; echo ; echo press any key to close ; read -r _"
