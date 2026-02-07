# CLAUDE.md

This file is the source of truth for project conventions and context. **Any change to the codebase — new files, dependencies, commands, architectural decisions, or gotchas — must be reflected here before finishing your work.** Keep every section accurate and up to date.

## Project Overview

Raycast menu bar extension ("Focus Bar") — a 25-minute focus timer that lives in the macOS menu bar. Built with React/TypeScript on the Raycast Extension API.

## Development Environment

- **Runtime:** Node.js 22 (provided by Nix flake)
- Nix flake dev shell with direnv integration (`.envrc` with `use flake`)
- Nixpkgs unstable channel, multi-system via `flake-utils`
- **Package manager:** npm (lockfile committed)

### Commands

| Command | Description |
|---------|-------------|
| `npm run dev` | Start Raycast development server (`ray develop`) |
| `npm run build` | Build for distribution (`ray build`) |
| `npm run lint` | Run ESLint |
| `npm run fix-lint` | Auto-fix lint issues |

## Project Structure

```
src/
  focus-bar.tsx   # Main MenuBarExtra component (single entry point)
assets/
  icon.png        # Extension icon
```

## Tech Stack

- **Language:** TypeScript (strict mode, target ES2021, CommonJS modules)
- **UI:** React JSX via Raycast `MenuBarExtra` component
- **API:** `@raycast/api`, `@raycast/utils`
- **Linting:** ESLint with `@raycast/eslint-config`
- **Formatting:** Prettier

## Conventions

- Commits use [Conventional Commits](https://www.conventionalcommits.org/) format: `type: description`
- Main branch: `main`

## Architecture Decisions

- Single-file component in `src/focus-bar.tsx` using Raycast's `MenuBarExtra` for menu bar presence
- Timer uses Raycast `Cache` to persist `endTime` (epoch ms); remaining time is computed on each render
- Background refresh at 10s interval (minimum allowed by Raycast) keeps the menu bar title updated
- Menu bar title shows `MM:SS` while running, hidden when idle (icon only)
- Raycast handles the build pipeline — no custom bundler config needed

## Gotchas

- Nix files must be staged in git before `nix flake update` will see them
- Raycast types are auto-generated in `raycast-env.d.ts` — do not edit manually
- MenuBarExtra commands are **not** long-lived processes — `setInterval`/`setState` won't update the menu bar. Use `Cache` + background refresh (`interval` in package.json) instead
- Minimum background refresh interval is `10s`; actual timing varies (macOS optimizes for energy)
