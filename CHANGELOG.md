# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.0.0] - 2026-09-01

### Added
- **Bar Widget (`BarWidget.qml`)**: Real-time streak pill (`🔥 45`) with dynamic color coding (Accent Green for completed, Urgent Amber for pending).
- **Interactive Popup Panel (`Panel.qml`)**:
  - Full multilingua course breakdown with flags (🇬🇧, 🇯🇵, 🇮🇹, 🇧🇷, etc.) and XP progress bars.
  - Keyboard navigation (`j`/`k` to select course, `Enter` to practice, `r` to refresh, `s` for settings, `Esc` to close).
  - One-click launcher for `duolingo-desktop-bin` and PWA webapps.
- **Background Service (`Service.qml`)**:
  - Smart evening streak reminders (notifies user if streak is in danger at 20:00).
  - Background stats synchronization with caching in `~/.local/state/omarchy/duolingo-cache.json`.
- **Zero-Config Auto Detection (`bin/detect-user.py`)**: Automatically detects username from local Duolingo desktop or browser Redux session stores.
- **Interactive Setup Wizard (`install.sh`)**: Built with `gum` to select bar placement (left, center, right) and configure hotkeys (`SUPER + CTRL + D`).
- **Clean Uninstaller (`uninstall.sh`)**: Safely removes plugin, clears bar configuration, and purges state.
