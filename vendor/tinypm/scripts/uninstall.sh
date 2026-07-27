#!/usr/bin/env bash
set -euo pipefail

PREFIX="${TINYPM_PREFIX:-$HOME/.tinypm}"
LOCAL_BIN="$HOME/.local/bin"
CONFIG_DIR="${XDG_CONFIG_HOME:-$HOME/.config}/tinypm"
STATE_DIR="${XDG_STATE_HOME:-$HOME/.local/state}/tinypm"
DATA_HOME="${XDG_DATA_HOME:-$HOME/.local/share}"
FISH_COMPLETIONS="${XDG_CONFIG_HOME:-$HOME/.config}/fish/completions"

echo "[TinyPM] Removing runtime from $PREFIX ..."
rm -rf "$PREFIX"
for cmd in tinypm tiny grab grab-add-repo grab-de syspm version _spinner Forge Parcel; do
    rm -f "$LOCAL_BIN/$cmd"
done
for cmd in tinypm tiny grab grab-add-repo grab-de syspm; do
    rm -f "$DATA_HOME/bash-completion/completions/$cmd"
    rm -f "$FISH_COMPLETIONS/$cmd.fish"
done
rm -f "$DATA_HOME/zsh/site-functions/_tinypm"
rm -rf "$CONFIG_DIR"
rm -rf "$STATE_DIR"
echo "[TinyPM] Uninstallation complete!"
