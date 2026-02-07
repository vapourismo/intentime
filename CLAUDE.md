# CLAUDE.md

This file is the source of truth for project conventions and context. **Any change to the codebase — new files, dependencies, commands, architectural decisions, or gotchas — must be reflected here before finishing your work.** Keep every section accurate and up to date.

## Project Overview

Focus Bar — a 25-minute focus timer that lives in the macOS menu bar. Native Swift app using SwiftUI's `MenuBarExtra`.

## Development Environment

- **Language:** Swift (requires Xcode and macOS SDK)
- Nix flake dev shell with direnv integration (`.envrc` with `use flake`)
- Nixpkgs unstable channel, multi-system via `flake-utils`
- **Build system:** Swift Package Manager

### Commands

| Command | Description |
|---------|-------------|
| `swift build` | Build the app |
| `swift run` | Build and run the menu bar app |
| `swift build -c release` | Release build |

## Project Structure

```
Package.swift                  # SwiftPM manifest
Sources/FocusBar/
  FocusBarApp.swift            # @main App struct with MenuBarExtra scene
  TimerModel.swift             # ObservableObject managing countdown + persistence
```

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** SwiftUI `MenuBarExtra` (macOS 14+)
- **Persistence:** `UserDefaults`
- **Build:** Swift Package Manager (executable target)

## Conventions

- Commits use [Conventional Commits](https://www.conventionalcommits.org/) format: `type: description`
- Main branch: `main`

## Architecture Decisions

- SwiftPM executable target (no Xcode project needed)
- SwiftUI `MenuBarExtra` for menu bar presence — deployment target macOS 14
- Dock icon hidden via `NSApplication.setActivationPolicy(.accessory)`
- Timer uses `UserDefaults` to persist `endTime` (epoch seconds); remaining time is computed on each tick
- 1-second timer via `Timer.publish(every: 1, on: .main, in: .common)` — fires even when menu is open
- Menu bar title shows `MM:SS` while running, hidden when idle (icon only)
- `ObservableObject` pattern for timer state (macOS 14 compatible)

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- The flake uses `mkShellNoCC` and unsets `SDKROOT`/`DEVELOPER_DIR`/`NIX_CFLAGS_COMPILE`/`NIX_LDFLAGS` in `shellHook` — Nix's default darwin SDK is incompatible with the Xcode Swift toolchain
- `MenuBarExtra` requires macOS 13+; we target macOS 14 for stable behavior
- `Timer.publish` must use `.common` RunLoop mode, otherwise the timer pauses when the menu dropdown is open
- The app is a menu-bar-only app (no main window); `NSApplication.setActivationPolicy(.accessory)` hides the Dock icon
- A "Quit" menu item is essential since there's no Dock icon to right-click for quitting
