# CLAUDE.md

This file is the source of truth for project conventions and context. **Any change to the codebase — new files, dependencies, commands, architectural decisions, or gotchas — must be reflected here before finishing your work.** Keep every section accurate and up to date.

## Project Overview

Focus Bar — a 25-minute focus timer that lives in the macOS menu bar. Native Swift app using AppKit's `NSStatusItem`.

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
  FocusBarApp.swift            # @main entry point, AppDelegate with NSStatusItem + NSMenu
  TimerModel.swift             # ObservableObject managing countdown + persistence
```

## Tech Stack

- **Language:** Swift 5.9+
- **UI:** AppKit `NSStatusItem` + `NSMenu`
- **Persistence:** `UserDefaults`
- **Build:** Swift Package Manager (executable target)

## Conventions

- Commits use [Conventional Commits](https://www.conventionalcommits.org/) format: `type: description`
- Main branch: `main`

## Architecture Decisions

- SwiftPM executable target (no Xcode project needed)
- AppKit `NSStatusItem` + `NSMenu` for menu bar presence (SwiftUI `MenuBarExtra` label does not reliably update from `ObservableObject` state changes)
- Dock icon hidden via `NSApplication.setActivationPolicy(.accessory)`
- Timer state lives in `TimerModel` (`ObservableObject`); the `AppDelegate` subscribes to `objectWillChange` and rebuilds the `NSStatusItem` button title and `NSMenu` on each change
- Timer uses `UserDefaults` to persist `endTime` (epoch seconds); remaining time is computed on each tick
- 1-second timer via `Timer.publish(every: 1, on: .main, in: .common)` — fires even when menu is open
- Starting a session shows an `NSAlert` with a text field prompting for a focus message; the message is persisted in `UserDefaults`
- Timer is NOT auto-restored on launch; instead, a "Continue Previous Session" menu item appears when a previous session is still valid, letting the user choose to resume
- Menu bar title shows `MM:SS — message` while running (or just `MM:SS` if no message), icon only when idle

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- The flake uses `mkShellNoCC` and unsets `SDKROOT`/`DEVELOPER_DIR`/`NIX_CFLAGS_COMPILE`/`NIX_LDFLAGS` in `shellHook` — Nix's default darwin SDK is incompatible with the Xcode Swift toolchain
- SwiftUI `MenuBarExtra` does not reliably re-render its label from `@StateObject`/`@ObservedObject` changes — this is why we use AppKit `NSStatusItem` instead
- `Timer.publish` must use `.common` RunLoop mode, otherwise the timer pauses when the menu dropdown is open
- The app is a menu-bar-only app (no main window); `NSApplication.setActivationPolicy(.accessory)` hides the Dock icon
- A "Quit" menu item is essential since there's no Dock icon to right-click for quitting
