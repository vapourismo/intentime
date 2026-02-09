# AGENTS.md

This file is the source of truth for project conventions and context for Codex agents. Any change to the codebase (new files, dependencies, commands, architectural decisions, or gotchas) must be reflected here before finishing work. Keep every section accurate and up to date.

## Project Overview

Intentime - a Pomodoro timer that lives in the macOS menu bar. Cycles through work sessions and breaks (configurable durations; defaults: 25-minute work, 5-minute short break, 20-minute long break after every 4 sessions). Native Swift app using AppKit's `NSStatusItem`.

## Development Environment

- Language: Swift (requires Xcode and macOS SDK)
- Nix flake dev shell with direnv integration (`.envrc` with `use flake`)
- Nixpkgs unstable channel, multi-system via `flake-utils`
- Build system: Swift Package Manager

### Commands

| Command | Description |
|---------|-------------|
| `swift build` | Build the app |
| `swift run` | Build and run the menu bar app |
| `swift build -c release` | Release build |
| `nix build --no-link .#` | Build the flake package (installs `bin/intentime` and `Applications/Intentime.app`) |
| `nix run .#` | Launch the flake app via `open -a` on `Applications/Intentime.app` |
| `./scripts/generate-icon.sh` | Render template logo + generate `Resources/AppIcon.icns` |
| `./scripts/bundle.sh` | Build release + assemble `build/Intentime.app` bundle |
| `./scripts/bundle.sh --sign` | Build release + bundle + ad-hoc codesign |

## Project Structure

```
Package.swift                  # SwiftPM manifest
Info.plist                     # App bundle metadata (CFBundleIdentifier, LSUIElement, etc.)
assets/
  AppIcon-1024.png             # Generated 1024x1024 logo source image used for iconset scaling
Resources/
  AppIcon.icns                 # App bundle icon copied into Contents/Resources
Sources/Intentime/
  IntentimeApp.swift           # @main entry point, AppDelegate with NSStatusItem + NSMenu
  GlobalHotKey.swift           # Carbon RegisterEventHotKey wrapper for system-wide shortcuts
  TimerModel.swift             # Pomodoro state machine managing phases, countdown + persistence
  Settings.swift               # Singleton holding user-configurable durations, persisted in UserDefaults
scripts/
  bundle.sh                    # Builds release binary and assembles Intentime.app
  generate-icon.sh             # Generates iconset sizes and outputs Resources/AppIcon.icns
  generate_icon.swift          # Draws the stopwatch-style app logo PNG template
build/                         # Bundle output (gitignored)
  Intentime.app/               # The assembled macOS app bundle
```

## Tech Stack

- Language: Swift 5.9+
- UI: AppKit `NSStatusItem` + `NSMenu`
- Persistence: `UserDefaults`
- Build: Swift Package Manager (executable target)

## Conventions

- Commits use [Conventional Commits](https://www.conventionalcommits.org/) format: `type: description`
- Main branch: `main`

## Architecture Decisions

- SwiftPM executable target (no Xcode project needed)
- Flake exports `packages.intentime` via a sandboxed Nix derivation using `swiftPackages.stdenv.mkDerivation` with `swift` + `swiftpm` in `nativeBuildInputs`; the helper-provided build phase performs a release SwiftPM build and `installPhase` assembles `$out/Applications/Intentime.app` (binary, `Info.plist`, `Resources`, `PkgInfo`) and symlinks `$out/bin/intentime` to the app executable. `packages.default` is defined as `self.packages.${system}.intentime`. Flake also exports `apps.intentime`/`apps.default`, which run a tiny launcher script that executes `open -a "$storePath/Applications/Intentime.app"` so `nix run` opens the app bundle instead of invoking the raw executable
- AppKit `NSStatusItem` + `NSMenu` for menu bar presence (SwiftUI `MenuBarExtra` label does not reliably update from `ObservableObject` state changes)
- Dock icon hidden via `NSApplication.setActivationPolicy(.accessory)`
- Timer state lives in `TimerModel`; the `AppDelegate` uses a 0.5s `Timer` scheduled in `.common` RunLoop mode to poll the model and update the `NSStatusItem` button title/image - this fires even during `NSMenu` event tracking. The menu is rebuilt on demand via `NSMenuDelegate.menuNeedsUpdate(_:)`
- Pomodoro cycle: work -> short break -> repeat; after N work sessions -> long break -> cycle restarts. All durations and session count are configurable via `Settings` (persisted in `UserDefaults`; defaults: 25/5/20 min, 4 sessions). Work->break transitions happen automatically. When a break ends, the app pauses and shows a floating HUD prompt (`NSPanel`) with "Resume Work", "+N min", and "Stop" buttons (the menu shows "Extend Break (+N min)") - the next work session only starts after user confirmation. The extend-break duration is configurable (default: 5 min). Current phase and pomodoro count are persisted in `UserDefaults`
- Settings are accessible via a "Settings" menu item (Cmd+,). The settings panel is a floating `NSPanel` with a standard macOS title bar plus translucent content, a title/subtitle header, rounded form card, number fields plus steppers for work duration, short break, long break, extend break (all in minutes), sessions before long break, a checkbox for blur screen during breaks, and Save/Cancel actions. Settings number fields are borderless editable `NSTextField`s centered inside rounded background container views for consistent vertical alignment. Changes take effect on the next phase (the currently running phase keeps its original duration)
- Opt-in screen blur overlay during breaks: when enabled in Settings, a full-screen `NSVisualEffectView` (`.behindWindow`, `.fullScreenUI` material) with a very light dark tint (black at 2% opacity) covers all displays during breaks. The overlay window itself fades in to 85% opacity so the blur is more pronounced while still leaving context visible. Uses one borderless `NSWindow` per screen at `.floating` level with `ignoresMouseEvents = true` (click-through). No special permissions needed. The break-end prompt and phase banner panels are elevated to `.floating + 1` so they remain interactive above the blur. Blur activates for both automatic and manual ("Go to Break") break starts, persists through extended breaks, and is dismissed on resume work/stop/skip
- Notifications use floating `NSPanel` (HUD style) banners instead of `UNUserNotificationCenter` because SwiftPM executables lack a bundle identifier. Break-start banners auto-dismiss after 4 seconds and a full-screen orange border glow animation runs for 15 seconds total (0.5-second hold then fade); when a break ends, the same border animation runs in green for 2 seconds total and the break-end prompt persists until the user responds. Break-start banners dynamically size to the title/body text (with multi-line body wrapping when needed) to avoid clipped copy. Break-start banner body copy and break-end prompt body copy are randomized from pools of 20 cheeky variants each while preserving the original intent
- Timer uses `UserDefaults` to persist `endTime` (epoch seconds); remaining time is computed on each tick. Paused state is persisted as `pausedSecondsLeft` (integer) - on pause the end time is cleared and remaining seconds saved; on unpause a new end time is computed
- Timer and message are independent: the timer can be started/stopped without setting a message, and a message can be set/cleared without a running timer
- Message is persisted in `UserDefaults` and restored on launch (independent of timer state)
- Timer is not auto-restored on launch; instead, a "Continue Previous Session" menu item appears when a previous session is still valid, letting the user choose to resume
- Timer can be paused and resumed during work phases; paused state survives app restart via `UserDefaults`. Users can skip any phase ("Go to Break" or "End Break")
- Menu bar title behavior is unchanged for non-break contexts: `MM:SS — message` (timer with message), `MM:SS` (timer only), or `message` (message only). During active short/long breaks, the message portion is replaced by randomized break-encouragement copy (picked from phase-specific pools and kept stable for that break). Break encouragement lines are action-oriented, witty, and do not use periods. During work, the icon is a custom-drawn progress circle (pie chart filling clockwise from 12 o'clock). During breaks, the icon is `cup.and.saucer.fill`. When paused, the icon changes to `pause.fill`. Idle/fallback icon uses the app logo (`AppIcon.icns`), trims transparent padding so it renders larger in the status item, and falls back to `clock` if the logo cannot be loaded
- System-wide hotkey (Cmd+Shift+Space) opens a Spotlight-like HUD panel for setting the focus message. Uses Carbon `RegisterEventHotKey` (no Accessibility permissions needed, works without a bundle identifier). The same panel is used by the "Set Message" / "Edit Message" menu item. Enter confirms, Escape cancels, pressing the hotkey again toggles the panel closed
- The app is distributed as a macOS `.app` bundle (`build/Intentime.app`), assembled by `scripts/bundle.sh`. The bundle includes `Info.plist` with `CFBundleIdentifier = com.intentime.app`, `CFBundleIconFile = AppIcon`, and `LSUIElement = true` (belt-and-suspenders with `setActivationPolicy(.accessory)`). `Info.plist` is a static file checked into the repo. `PkgInfo` is generated by the script. `scripts/bundle.sh` copies everything in `Resources/` into `Contents/Resources` so `Resources/AppIcon.icns` ships in the bundle. The `build/` output directory is gitignored
- App logo source is generated (not hand-drawn in external tools): `scripts/generate_icon.swift` renders a stopwatch icon template (scaled up to reduce transparent padding in the final app icon) and `scripts/generate-icon.sh` scales it into an `.iconset` and compiles `Resources/AppIcon.icns` via `iconutil`

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- The flake defines a single dev shell (`devShells.default`) and it does not explicitly export SDK/toolchain environment variables. Depending on the active nix toolchain wrappers, your shell may still show variables such as `SDKROOT`, `DEVELOPER_DIR`, `NIX_CFLAGS_COMPILE`, `NIX_LDFLAGS`, and `MACOSX_DEPLOYMENT_TARGET`, and `swift build` may print target/deployment warnings (for example `--target arm64-apple-macosx12.0` vs `-mmacos-version-min=14.0`). `.envrc` currently contains only `use flake`
- SwiftUI `MenuBarExtra` does not reliably re-render its label from `@StateObject`/`@ObservedObject` changes - this is why we use AppKit `NSStatusItem` instead
- App timers must use `.common` RunLoop mode (`Timer(...)` + `RunLoop.main.add(..., forMode: .common)`), otherwise timer/status updates pause when the menu dropdown is open
- The app is a menu-bar-only app (no main window); `NSApplication.setActivationPolicy(.accessory)` hides the Dock icon
- A "Quit" menu item is essential since there's no Dock icon to right-click for quitting
- UserDefaults domain changes with bundle: when running as a bare executable (`swift run`), `UserDefaults.standard` uses the executable name as its domain. When running from the `.app` bundle, it uses the `CFBundleIdentifier` (`com.intentime.app`). Settings/timer state saved by one form will not be visible to the other
