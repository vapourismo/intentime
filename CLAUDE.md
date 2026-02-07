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
- Timer state lives in `TimerModel` (`ObservableObject`); the `AppDelegate` uses a 0.5s `Timer` scheduled in `.common` RunLoop mode to poll the model and update the `NSStatusItem` button title/image — this fires even during `NSMenu` event tracking. The menu is rebuilt on demand via `NSMenuDelegate.menuNeedsUpdate(_:)`
- Timer uses `UserDefaults` to persist `endTime` (epoch seconds); remaining time is computed on each tick. Paused state is persisted as `pausedSecondsLeft` (integer) — on pause the end time is cleared and remaining seconds saved; on unpause a new end time is computed
- 1-second timer via `Timer.publish(every: 1, on: .main, in: .common)` — fires even when menu is open
- Timer and message are independent: the timer can be started/stopped without setting a message, and a message can be set/cleared without a running timer
- Message is persisted in `UserDefaults` and restored on launch (independent of timer state)
- Timer is NOT auto-restored on launch; instead, a "Continue Previous Timer" menu item appears when a previous session is still valid, letting the user choose to resume
- Timer can be paused and resumed; paused state survives app restart via `UserDefaults`
- Menu bar title shows `MM:SS — message` (both active), `MM:SS` (timer only), or `message` (message only); icon only when both are inactive. When the timer is active, the icon is a custom-drawn progress circle (pie chart filling clockwise from 12 o'clock) rendered via Core Graphics as a template image. When paused, the icon changes to `pause.circle`

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- **Nix + Swift SDK mismatch:** Nix injects `SDKROOT`, `DEVELOPER_DIR`, `NIX_CFLAGS_COMPILE`, `NIX_LDFLAGS`, `MACOSX_DEPLOYMENT_TARGET` pointing to an old Apple SDK incompatible with the host Xcode Swift compiler. The `.envrc` unsets these after `use flake` so `swift build` just works. If you see `failed to build module 'Swift'; this SDK is not supported by the compiler`, check that these vars are unset. Note: `shellHook` in `flake.nix` only runs in interactive `nix develop` — `direnv` does NOT execute it, which is why the unset must live in `.envrc`
- SwiftUI `MenuBarExtra` does not reliably re-render its label from `@StateObject`/`@ObservedObject` changes — this is why we use AppKit `NSStatusItem` instead
- `Timer.publish` must use `.common` RunLoop mode, otherwise the timer pauses when the menu dropdown is open
- The app is a menu-bar-only app (no main window); `NSApplication.setActivationPolicy(.accessory)` hides the Dock icon
- A "Quit" menu item is essential since there's no Dock icon to right-click for quitting
