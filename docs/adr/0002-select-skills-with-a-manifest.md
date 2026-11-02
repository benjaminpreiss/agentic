---
status: accepted
---
# Select skills with a checked-in manifest

The shared deployment toolkit archives a reviewed consumer commit and rejects symlinks so that staged Nix inputs cannot follow paths outside source. Agentic therefore selects skills through `skills/enabled.nix`, mapping installed names to validated paths under `skills/available/`, instead of checked-in links. New NixOS builds use the manifest directly; the old manual staging script temporarily reconstructs the same links for existing hosts until their non-destructive migration. This supersedes [ADR 0001](0001-select-skills-with-checked-in-symlinks.md).
