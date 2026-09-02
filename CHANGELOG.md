# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.0.0),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [1.5.0] - 2026-09-02

### Security (marketplace review fixes)

- **Opt-in local scan**: `autoDetect` now defaults to `false`. Enabling the widget never reads local browser/app storage until you explicitly opt in; the manifest label and README Privacy section disclose the exact scanned paths and the single extracted field (`user.username`) before the first scan.
- **Hardened file I/O (`bin/duoio.py`)**: all state/cache access is descriptor-bound (`O_NOFOLLOW|O_NONBLOCK`, fstat-verified regular files — no symlink/fifo races or wedges), size-capped reads, exclusive `0600` atomic writes via rename under a pinned directory fd, revision revalidation before rename, and fsync of file and directory.
- **Bounded scanning (`bin/detect-user.py`)**: base64 decode, gzip expansion (capped at 4 MiB decompressed), JSON parsing, and regex match collection (max 64 per file) now run under hard caps with a 20 s deadline and 16/64 MiB per-file/total budgets, so storage-controlled data cannot expand beyond memory or time bounds.
- **Bounded fetching (`bin/fetch-duo.py`)**: the HTTP response is streamed under a 1 MiB ceiling with a producer deadline instead of an unbounded read; responses are schema-validated (cardinality, field types, string lengths, course count) and projected to a small normalized JSON document, so the QML side never buffers attacker-sized stdout and the raw upstream blob is never cached or emitted.
- **No secrets in argv (`bin/state-io.py`)**: the private history JSON travels to the writer over stdin with a size cap instead of `bash -c` process arguments, which are world-readable via `/proc/<pid>/cmdline`.

### Changed

- Test suite (43 stdlib `unittest` tests) covering the io helper, scanner limits, fetch schema validation, and state I/O including symlink-refusal and revision conflicts.

## [1.4.0] - 2026-09-02

### Added
- **Privacy opt-out (`autoDetect`)**: New boolean setting `autoDetect` (default `true`) to control local username scan. When `username` is empty and `autoDetect` is false, `Service` passes `--no-detect` to `fetch-duo.py` which skips `detect-user.py` LevelDB scan and returns cached data or an error, preserving zero-config while allowing privacy-conscious users to disable local storage access. Panel toggle mirrors `reducedMotion`/`showXp` pattern. Manifest bumped to 1.4.0.

### Fixed
- **Offline reminder catch-up**: Add bounded per-day catch-up (`lastCatchUpDate`) that fires once after `historyLoaded` when the clock is past `remindHour` and the fetch has failed (`lastError` or invalid `userData`), using the restored `history.json` snapshot to check `streakExtendedToday` via `Model.dayKey`. Prevents missed reminders when the PC boots late with no network. Guarded to run only when `userData` is invalid, only once per day, and not when today's snapshot shows the streak already completed.

## [1.3.0] - 2026-09-01

### Added
- **Overlay (`Overlay.qml` + `Commands.js`)**: Full-screen PanelWindow (`WlrLayershell` Overlay/Exclusive, `duolingo-overlay` namespace) with `open(payloadJson)`/`finishClose()->shell.hide("user.duolingo")` lifecycle, focused-screen resolution, dark scrim (0.78) with green gradient, and `Commands.js` verb grammar mirroring hydrate's contract (`score`/`verbScore`/`suggest`/`parse`/`execute`/`contextOf`/`helpRows`).
- **Command palette**: Ghost completion, suggestions list (Up/Down, Tab to accept), live preview row, toast feedback, shake on error, `PgUp`/`PgDn` pane cycling. Panes: `today` (goal + streak + courses), `history` (recent days from `history.json`), `help` (all verbs). `Esc` clears input first, then closes. `Enter` submits. `reducedMotion` disables ignition sweep and shortens transitions.
- **Verbs**: `practice` (launch), `refresh`, `open`/`panel` (close overlay), `username <name>` (persist via `shell.updateEntryInline`, validated `^[A-Za-z0-9_.-]{2,25}$`), `goal <n>` (10-1000, bare number also sets goal), `streak`/`xp`/`today` (read-only info), `history`/`help`/`?` (pane switches), `quit`/`q`/`close`/`exit` (close). Unknown input shows suggestions, never executes.
- **Service IPC**: `shell.toggle("user.duolingo")` overlay entry point, `runCommand(text)` + `IpcHandler` actions `overlay` and `run` (extend `user.duolingo` target). Helpers `setUsername`/`setGoal`/`setSettings` via `updateEntryInline`. Bar tooltip now mentions overlay access.
- **Hero visual**: Large streak number + `xpToday / goalXp` arc (270 degree `Shape` track + progress with glow + tick ring, ignition sweep on open), week strip reuse of `weekHistory`, subtle `duo.svg` feather at low opacity.
- **Manifest**: Added `overlay` to `kinds` and `entryPoints {overlay:"Overlay.qml"}` (order `bar-widget`, `overlay`, `service` like hydrate). Version bump to 1.3.0.

## [1.2.0] - 2026-09-01

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
