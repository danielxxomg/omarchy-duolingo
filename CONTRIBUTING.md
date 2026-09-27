# Contributing to omarchy-duolingo

Thank you for your interest in contributing to `omarchy-duolingo`! This document details guidelines, setup prerequisites, testing procedures, and coding standards.

---

## Project Overview

`omarchy-duolingo` is a native desktop status widget and interactive panel for [Omarchy](https://github.com/omarchy) / Quattro, powered by [Quickshell](https://quickshell.outfoxxed.me/). It provides:
- Live streak tracking with freeze and daily extension status.
- Today XP progress against configurable daily goals.
- Weekly XP history visualizations.
- Active language courses, crowns, and XP breakdown.
- Privacy-conscious local caching, secure I/O, and non-blocking background fetching.

---

## Prerequisites

Before contributing, ensure your development environment has the following tools installed:

- **Python**: version 3.10 or higher (`python3 --version`)
- **Node.js**: version 20 or higher (`node --version`)
- **Quickshell / Omarchy**: for running and previewing the desktop UI components (`BarWidget.qml`, `Panel.qml`, `Overlay.qml`)
- **Git**: for version control and patch submissions

Optional:
- `pre-commit`: to automatically check formatting and run tests before committing.

---

## Getting Started

1. **Clone the repository**:
   ```bash
   git clone https://github.com/danielxxomg/omarchy-duolingo.git
   cd omarchy-duolingo
   ```

2. **Verify helper permissions**:
   Ensure executable permissions on helper scripts:
   ```bash
   chmod +x bin/fetch-duo.py bin/detect-user.py bin/state-io.py bin/launch-duo.sh
   ```

3. **Install pre-commit hooks (optional)**:
   ```bash
   pre-commit install
   ```

---

## Running the Test Suite

All unit tests must pass cleanly before submitting any pull request.

### Python Unit Tests
The Python test suite validates secure I/O, bounded fetching, upstream schema parsing, and CLI contract adherence:
```bash
python3 -m unittest discover tests -v
```

### Node.js Contract Tests
The Node.js test suite tests the QML JavaScript business logic (`Model.js` and `Commands.js`):
```bash
node --test tests/model-commands.test.mjs
```
You can also run all Node tests via:
```bash
node --test tests/*.test.mjs
```

---

## Commit Message Conventions

This project enforces [Conventional Commits](https://www.conventionalcommits.org/en/v1.0.0/).

### Format
```
<type>(<scope>): <short description>

[optional body]

[optional footer(s)]
```

### Types
- `feat`: A new feature or product enhancement
- `fix`: A bug fix
- `docs`: Documentation changes only
- `style`: Changes that do not affect the meaning of code (formatting, white-space, etc.)
- `refactor`: A code change that neither fixes a bug nor adds a feature
- `test`: Adding missing tests or correcting existing tests
- `chore`: Maintenance tasks, dependencies, tooling, or build configuration

### Rules
- Default to **English** for all commit messages, code, comments, documentation, and tests.
- **Never include AI attribution or "Co-Authored-By" tags** in commit messages or pull request descriptions.
- Keep the first line concise (under 72 characters) and imperative (e.g., `feat: add super badge` instead of `feat: added super badge`).

---

## Code Style & Security Guidelines

- **Privacy & Security First**:
  - Never project or cache Duolingo legal names or sensitive personal information. Public username doubles as the identifier.
  - All file I/O must be descriptor-bound, no-follow, size-capped, and use atomic writes where applicable (refer to `duoio.py`).
  - Network responses must be bounded in byte size and timeout-governed.
- **Separation of Concerns**:
  - Keep business logic, mathematical calculations, and parsing inside `Model.js` or `bin/fetch-duo.py`.
  - QML components (`Panel.qml`, `BarWidget.qml`, `Overlay.qml`) should focus strictly on UI presentation, user interactions, and reactive bindings.
- **Completeness**:
  - Any new helper output or model function must include corresponding unit tests in `tests/test_fetch_duo.py` and `tests/model-commands.test.mjs`.
