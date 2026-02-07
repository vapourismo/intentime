# CLAUDE.md

This file is the source of truth for project conventions and context. Keep it up to date: when you discover something important during a session (new tooling, conventions, gotchas, architectural decisions), add it to the relevant section below before finishing your work.

## Development Environment

- Nix flake dev shell with direnv integration (`.envrc` with `use flake`)
- Nixpkgs unstable channel, multi-system via `flake-utils`
- Nix files must be staged in git before `nix flake update` will see them

## Architecture Decisions

<!-- Record significant design choices and their rationale here -->

## Gotchas

<!-- Record surprising behaviours, workarounds, or common mistakes here -->
