# Duolingo Plugin for Omarchy 🦉🔥

A language learning companion for the **Omarchy** Linux desktop and Hyprland bar.

Track your daily Duolingo streak in real-time, view your multilingual learning progress with language flags, get evening reminder notifications when your streak is at risk, and launch your practice session with a single keypress.

---

## ✨ Features

- **🔥 Real-Time Streak Indicator (`BarWidget.qml`)**:
  - Live flame glyph with your current day streak (e.g. `🔥 45`).
  - Adaptive theme colors: **Accent Green** when your daily streak is secured, **Urgent Amber** when you still need to practice.
  - Quick actions: Left click opens popup panel, Right click launches Duolingo, Middle click refreshes.
- **📊 Multilingual Course Breakdown (`Panel.qml`)**:
  - Displays all your enrolled languages with flags (🇬🇧 English, 🇯🇵 Japanese, 🇮🇹 Italian, 🇧🇷 Portuguese, 🇪🇸 Spanish, etc.) and XP progress bars.
  - Total XP, profile info, and streak status banner.
- **⏰ Smart Evening Streak Reminders (`Service.qml`)**:
  - Background daemon checks your streak status.
  - Automatically emits a desktop notification at 20:00 (configurable) if you haven't completed your lesson today.
- **🧠 Zero-Config Auto Detection (`bin/detect-user.py`)**:
  - Reads your local Duolingo desktop or browser Redux session store and resolves your username automatically.
- **🎯 Universal Linux Client Support (`bin/launch-duo.sh`)**:
  - Automatically detects and launches your preferred Duolingo client: Native AUR binary, Flatpak DL-Desktop, Omarchy WebApp, or default browser.
- **⌨️ Keyboard-First (`PanelKeyCatcher`)**:
  - `j` / `k` (or Arrow keys): Navigate between language courses.
  - `Enter`: Launch Duolingo and start practicing.
  - `r`: Refresh live stats from Duolingo API.
  - `s`: Toggle settings drawer.
  - `Esc` or `q`: Close popup.
- **🧪 Full IPC Support**:
  - Query stats or trigger actions from bash scripts, Waybar, or custom keybindings.

---

## 🌐 Supported Linux Duolingo Ecosystem

This plugin serves as the status bar companion for the entire Linux Duolingo ecosystem:

| Tool | Type | Source | Compatibility |
| :--- | :--- | :--- | :--- |
| **[DL-Desktop](https://github.com/hmlendea/dl-desktop)** | Dedicated Desktop Client | AUR (`duolingo-desktop-bin`) / Flatpak (`com.github.hmlendea.DL-Desktop`) | Supported (Auto-launch & Auto-detect) |
| **Omarchy WebApp** | Lightweight PWA | `omarchy webapp install "Duolingo" "https://www.duolingo.com"` | Supported (Auto-launch) |
| **[AnkiSyncDuolingo](https://github.com/AnkiSyncDuolingo)** | SRS Vocabulary Synchronizer | GitHub / AnkiWeb Add-on | Recommended companion for long-term retention |

---

## 🚀 Installation

### Option 1: Via Git (Recommended)

```bash
omarchy plugin add https://github.com/danielxxomg/omarchy-duolingo --enable
```

### Option 2: Interactive Installer

Clone or drop this repository into `~/.config/omarchy/plugins/user.duolingo` and run:

```bash
~/.config/omarchy/plugins/user.duolingo/install.sh
```

---

## ⌨️ Hyprland Keybinding

Add this to `~/.config/hypr/bindings.lua`:

```lua
o.bind("SUPER + CTRL + D", "Duolingo Tracker", "omarchy-shell user.duolingo toggle")
```

---

## 🧪 CLI & IPC Commands

Control the plugin directly from terminal or scripts:

```bash
# Toggle the popup panel
omarchy-shell user.duolingo toggle

# Launch Duolingo app or webapp
omarchy-shell user.duolingo launch

# Force refresh stats from Duolingo API
omarchy-shell user.duolingo refresh

# Print one-line status summary
omarchy-shell duolingo status
```

---

## ⚙️ Configuration (`~/.config/omarchy/shell.json`)

All configuration is managed within your Omarchy `shell.json`:

```json
{
  "bar": {
    "layout": {
      "right": [
        {
          "id": "user.duolingo",
          "username": "",
          "refreshMinutes": 15,
          "showXp": false,
          "remindersEnabled": true,
          "remindHour": 20
        }
      ]
    }
  }
}
```

| Setting | Type | Default | Description |
| :--- | :--- | :--- | :--- |
| `username` | string | `""` (auto-detect) | Duolingo username. If empty, auto-detects from local session. |
| `refreshMinutes` | integer | `15` | Minutes between automatic API syncs. |
| `showXp` | boolean | `false` | When true, displays Total XP on the bar instead of streak. |
| `remindersEnabled` | boolean | `true` | Enables evening reminder notifications when streak is in danger. |
| `remindHour` | integer | `20` | Hour of the day (0-23) to trigger the streak reminder. |

---

## 🗑️ Uninstallation

```bash
omarchy plugin remove user.duolingo
```
Or run `~/.config/omarchy/plugins/user.duolingo/uninstall.sh`.

---

## 📄 License

MIT License © 2026 danielxxomg.
