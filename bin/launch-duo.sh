#!/bin/bash
# Universal Duolingo launcher for Linux / Omarchy

# 1. Native AUR / Pacman desktop binary
if command -v duolingo-desktop >/dev/null 2>&1; then
  setsid duolingo-desktop >/dev/null 2>&1 &
  exit 0
fi

if command -v dl-desktop >/dev/null 2>&1; then
  setsid dl-desktop >/dev/null 2>&1 &
  exit 0
fi

# 2. Flatpak DL-Desktop
if command -v flatpak >/dev/null 2>&1 && flatpak info com.github.hmlendea.DL-Desktop >/dev/null 2>&1; then
  setsid flatpak run com.github.hmlendea.DL-Desktop >/dev/null 2>&1 &
  exit 0
fi

# 3. Omarchy Webapp handler
if command -v omarchy-launch-webapp >/dev/null 2>&1; then
  omarchy-launch-webapp https://www.duolingo.com &
  exit 0
fi

# 4. Fallback: Default Browser
xdg-open https://www.duolingo.com >/dev/null 2>&1 &
