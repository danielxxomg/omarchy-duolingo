#!/bin/bash
set -e

PLUGIN_ID="user.duolingo"
PLUGIN_DIR="$HOME/.config/omarchy/plugins/$PLUGIN_ID"

echo -e "\e[32m=== Omarchy Duolingo Plugin Setup ===\e[0m\n"

# 1. Detect Username
DETECTED_USER=$("$PLUGIN_DIR/bin/detect-user.py" 2>/dev/null || echo "")
if command -v gum >/dev/null 2>&1; then
  if [[ -n "$DETECTED_USER" ]]; then
    echo -e "Found local Duolingo account: \e[33m$DETECTED_USER\e[0m"
    USER_CHOICE=$(gum choose "Use detected username ($DETECTED_USER)" "Enter different username")
    if [[ "$USER_CHOICE" == *"Enter different"* ]]; then
      USERNAME=$(gum input --prompt "Duolingo Username> " --placeholder "your_username")
    else
      USERNAME="$DETECTED_USER"
    fi
  else
    USERNAME=$(gum input --prompt "Duolingo Username> " --placeholder "your_username")
  fi

  # 2. Bar Section Placement
  echo -e "\nWhere would you like to place the Duolingo widget on the bar?"
  SECTION=$(gum choose "right" "center" "left")
else
  read -rp "Enter Duolingo username [$DETECTED_USER]: " USERNAME
  USERNAME="${USERNAME:-$DETECTED_USER}"
  read -rp "Bar section (right/center/left) [right]: " SECTION
  SECTION="${SECTION:-right}"
fi

# 3. Apply placement via omarchy bar
echo -e "\n\e[34mAdding widget to bar ($SECTION section)...\e[0m"
omarchy bar move "$PLUGIN_ID" --section "$SECTION" 2>/dev/null || omarchy bar put "$PLUGIN_ID" --section "$SECTION"

if [[ -n "$USERNAME" ]]; then
  if [[ ! "$USERNAME" =~ ^[A-Za-z0-9_.-]{2,25}$ ]]; then
    echo -e "\e[31mInvalid username \"$USERNAME\" — must match ^[A-Za-z0-9_.-]{2,25}$ — skipping bar set.\e[0m" >&2
  else
    if command -v jq >/dev/null 2>&1; then
      JSON_USER=$(jq -n --arg v "$USERNAME" '$v')
    else
      # Fallback: escape backslashes and quotes for JSON string
      ESCAPED=${USERNAME//\\/\\\\}
      ESCAPED=${ESCAPED//\"/\\\"}
      JSON_USER="\"$ESCAPED\""
    fi
    omarchy bar set "$PLUGIN_ID" "username" "$JSON_USER" --json 2>/dev/null || true
  fi
fi

# 4. Optional Hyprland Keybinding
BINDINGS_FILE="$HOME/.config/hypr/bindings.lua"
if [[ -f "$BINDINGS_FILE" ]] && ! grep -q "user.duolingo" "$BINDINGS_FILE"; then
  echo -e "\n\e[34mAdding SUPER + CTRL + D hotkey to $BINDINGS_FILE...\e[0m"
  echo -e '\no.bind("SUPER + CTRL + D", "Duolingo Tracker", "omarchy-shell user.duolingo toggle")' >> "$BINDINGS_FILE"
fi

# 5. Rescan and restart shell
echo -e "\n\e[32mRestarting shell to apply changes...\e[0m"
omarchy restart shell

echo -e "\n\e[32m✔ Duolingo plugin installed successfully!\e[0m"
echo -e "• Press \e[33mSUPER + CTRL + D\e[0m or click the widget on your bar to open."
