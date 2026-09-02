#!/bin/bash
set -e

PLUGIN_ID="user.duolingo"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"

echo -e "\e[33m=== Uninstalling Omarchy Duolingo Plugin ===\e[0m\n"

# 1. Disable widget (scoped, does not reset the entire bar)
echo -e "Disabling widget on Omarchy bar..."
omarchy plugin disable "$PLUGIN_ID" 2>/dev/null || omarchy-shell shell setPluginEnabled "$PLUGIN_ID" false 2>/dev/null || true

# 2. Clean keybindings
if [[ -f "$BINDINGS_FILE" ]]; then
  sed -i '/user.duolingo/d' "$BINDINGS_FILE"
fi

# 3. Purge cache
rm -rf "$HOME/.local/state/duolingo"
rm -f "$HOME/.local/state/omarchy/duolingo-cache.json"  # legacy path

# 4. Remove plugin directory
echo -e "Removing plugin files at $PLUGIN_DIR..."
rm -rf "$PLUGIN_DIR"

# 5. Restart shell
echo -e "Restarting shell..."
omarchy restart shell

echo -e "\e[32m✔ Plugin uninstalled successfully.\e[0m"
