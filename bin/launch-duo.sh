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

# 3. Existing Duolingo desktop entry (.desktop / ICE / WebApp)
for desktop in "$HOME"/.local/share/applications/*[Dd]uolingo*.desktop /usr/share/applications/*[Dd]uolingo*.desktop; do
  if [ -f "$desktop" ]; then
    if command -v gio >/dev/null 2>&1; then
      setsid gio launch "$desktop" >/dev/null 2>&1 &
      exit 0
    elif command -v gtk-launch >/dev/null 2>&1; then
      desktop_base=$(basename "$desktop" .desktop)
      setsid gtk-launch "$desktop_base" >/dev/null 2>&1 &
      exit 0
    else
      exec_cmd=$(grep -m1 '^Exec=' "$desktop" | cut -d= -f2- | sed 's/ %[uUfFdDnNickvm]//g')
      if [ -n "$exec_cmd" ]; then
        setsid sh -c "$exec_cmd" >/dev/null 2>&1 &
        exit 0
      fi
    fi
  fi
done

# 4. Omarchy Webapp handler
if command -v omarchy-launch-webapp >/dev/null 2>&1; then
  omarchy-launch-webapp https://www.duolingo.com &
  exit 0
fi

# 5. Fallback: Default Browser
xdg-open https://www.duolingo.com >/dev/null 2>&1 &
