# CLAUDE.md

This file is the source of truth for project conventions and context. **Any change to the codebase — new files, dependencies, commands, architectural decisions, or gotchas — must be reflected here before finishing your work.** Keep every section accurate and up to date.

## Project Overview

Focus Bar — a Pomodoro timer that lives in the macOS menu bar. Cycles through work sessions and breaks (configurable durations; defaults: 25-minute work, 5-minute short break, 20-minute long break after every 4 sessions). Native Swift app using AppKit's `NSStatusItem`.

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
  TimerModel.swift             # Pomodoro state machine managing phases, countdown + persistence
  Settings.swift               # Singleton holding user-configurable durations, persisted in UserDefaults
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
- Timer state lives in `TimerModel`; the `AppDelegate` uses a 0.5s `Timer` scheduled in `.common` RunLoop mode to poll the model and update the `NSStatusItem` button title/image — this fires even during `NSMenu` event tracking. The menu is rebuilt on demand via `NSMenuDelegate.menuNeedsUpdate(_:)`
- Pomodoro cycle: work → short break → repeat; after N work sessions → long break → cycle restarts. All durations and session count are configurable via `Settings` (persisted in `UserDefaults`; defaults: 25/5/20 min, 4 sessions). Work→break transitions happen automatically. When a break ends, the app pauses and shows a floating HUD prompt (NSPanel) with "Continue" and "Stop" buttons — the next work session only starts after user confirmation. Current phase and pomodoro count are persisted in `UserDefaults`
- Settings are accessible via a "Settings…" menu item (⌘,). The settings panel is a floating HUD `NSPanel` with number fields for work duration, short break, long break (all in minutes), and sessions before long break. Changes take effect on the next phase (the currently running phase keeps its original duration)
- Notifications use floating `NSPanel` (HUD style) banners instead of `UNUserNotificationCenter` because SwiftPM executables lack a bundle identifier. Break-start banners auto-dismiss after 4 seconds; break-end prompts persist until the user responds
- Timer uses `UserDefaults` to persist `endTime` (epoch seconds); remaining time is computed on each tick. Paused state is persisted as `pausedSecondsLeft` (integer) — on pause the end time is cleared and remaining seconds saved; on unpause a new end time is computed
- Timer and message are independent: the timer can be started/stopped without setting a message, and a message can be set/cleared without a running timer
- Message is persisted in `UserDefaults` and restored on launch (independent of timer state)
- Timer is NOT auto-restored on launch; instead, a "Continue Previous Session" menu item appears when a previous session is still valid, letting the user choose to resume
- Timer can be paused and resumed during work phases; paused state survives app restart via `UserDefaults`. Users can skip any phase (skip to break or skip break)
- Menu bar title shows `MM:SS — message` (timer with message), `MM:SS` (timer only), or `message` (message only); icon only when idle. During work, the icon is a custom-drawn progress circle (pie chart filling clockwise from 12 o'clock). During breaks, the icon is `cup.and.saucer.fill`. When paused, the icon changes to `pause.fill`

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- **Nix + Swift SDK mismatch:** Nix injects `SDKROOT`, `DEVELOPER_DIR`, `NIX_CFLAGS_COMPILE`, `NIX_LDFLAGS`, `MACOSX_DEPLOYMENT_TARGET` pointing to an old Apple SDK incompatible with the host Xcode Swift compiler. The `.envrc` unsets these after `use flake` so `swift build` just works. If you see `failed to build module 'Swift'; this SDK is not supported by the compiler`, check that these vars are unset. Note: `shellHook` in `flake.nix` only runs in interactive `nix develop` — `direnv` does NOT execute it, which is why the unset must live in `.envrc`
- SwiftUI `MenuBarExtra` does not reliably re-render its label from `@StateObject`/`@ObservedObject` changes — this is why we use AppKit `NSStatusItem` instead
- `Timer.publish` must use `.common` RunLoop mode, otherwise the timer pauses when the menu dropdown is open
- The app is a menu-bar-only app (no main window); `NSApplication.setActivationPolicy(.accessory)` hides the Dock icon
- A "Quit" menu item is essential since there's no Dock icon to right-click for quitting
