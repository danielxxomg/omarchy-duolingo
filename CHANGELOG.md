# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.2.0] - 2026-09-02

### Added
- **Local history**: Daily snapshots persisted to `~/.local/state/duolingo/history.json` with atomic mktemp+mv writes and rev guard; pruned to 366 days.
- **Daily XP goal**: `goalXp` setting (10-1000, default 50) with panel progress bar (green when met, amber otherwise) and bar tooltip `23 / 50 XP today`.
- **Week view**: 7-day compact strip (letter + vertical bar) derived from snapshots; placeholder on first day.
- **Settings face**: All schema keys reachable — username, goalXp presets (20/50/100/200) + stepper, refresh interval, showXp, reminders, remind hour, reducedMotion.
- **Empty states**: Username prompt with settings CTA, first-day placeholder, and preserved error banner.
- **Keyboard help**: `?` toggles aligned KeysCard (j/k, Enter, r, s, ?, Esc); footer hint retained.
- **Reduced motion**: `reducedMotion` setting disables panel animations via Behavior guards.

## [1.1.0] - 2026-09-01

### Fixed
- **Service ownership**: Service is now the single source of truth for data and fetch; BarWidget reads via `serviceFor` and pushes `widgetSettings` (fixes ignored reminders/hour and duplicate fetch).
- **Portability**: Replace hardcoded `HOME/.config/omarchy/plugins/user.duolingo` paths with `pluginDir` derived from `Qt.resolvedUrl(".")`.
- **Cache hygiene**: Move cache to `~/.local/state/duolingo/duolingo-cache.json` with atomic writes; stale fallback only on network/transport errors, not on HTTP 404.
- **Detection hardening**: `detect-user.py` skips symlinks, skips files >16MB and caps total reads at 64MB.
- **IPC consolidation**: Single `IpcHandler` target `user.duolingo` (`status`, `refresh`, `launch`, `streak`); panel toggle via shell id-based handling.
- **Date handling**: Use zero-padded `yyyy-mm-dd` via `Model.dayKey` for reminder gating.
- **Notifications**: Use `x-canonical-private-synchronous:duolingo` for replace semantics and `pluginDir/assets/duo.png` as icon; neutral copy without emoji.
- **Install/Uninstall**: Validate username against `^[A-Za-z0-9_.-]{2,25}$` with safe JSON quoting; uninstall now uses scoped `omarchy plugin disable` and cleans `~/.local/state/duolingo/`.

### Changed
- **Copy pass**: Remove emoji from all visible strings and tooltips; Panel banner surfaces errors and stale state; button labels neutral English.
- **Version**: Bump to 1.1.0, homepage now points to `https://github.com/danielxxomg/omarchy-duolingo`, `.gitignore` adds `.atl/`.

## [1.0.0] - 2026-09-01

### Added
- **Bar Widget (`BarWidget.qml`)**: Real-time streak pill (e.g. `45`) with dynamic color coding (Accent Green for completed, Urgent Amber for pending).
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
