# Agentic

A modular repository for building and maintaining an agentic machine. It brings together NixOS deployment, GitHub remote access and protection checks, sandboxed agents, and versioned skills. Pi and Oh My Pi are the current agent integrations, not the limits of the project. Installation and updates are scripted today; the layout keeps these responsibilities separate as deployment automation grows.

## Choose a task

| Task | Guide | Safety boundary |
| --- | --- | --- |
| Install NixOS on a new machine | [Install](docs/install.md) | **Erases the confirmed disk** using Disko. |
| Change an existing NixOS machine | [Update](docs/update.md) | Switches NixOS over SSH; **never runs Disko**. |
| Set up GitHub access and branch protections | [GitHub App](docs/github-app.md) | Private keys stay outside the flake and agent sandboxes. |
| Run sandboxed agents and select skills | [Sandbox and skills](docs/sandbox.md) | Only checked-in enabled skills are installed. |
| Upgrade a machine installed before PR #28 | [Upgrade notes](docs/skills-migration.md) | Existing skills are not removed automatically. |

## Repository map

- `nixos/`: flake, system modules and local nono profiles.
- `scripts/install/`, `scripts/update/`: operator workflows. Both use `scripts/stage.sh` to build the credential-free deployment source.
- `scripts/runtime/`, `scripts/github/`, `github-protection/`: host-side GitHub credentials, setup and protection audits.
- `skills/available/`: reviewed, versioned skills. Checked-in links under `skills/enabled/` are the sole installation selection; see the [decision record](docs/adr/0001-select-skills-with-checked-in-symlinks.md).
- `docs/`: task guides, security guidance and decisions.

`.deployment/` holds generated machine configuration and the Nix lock file. Keep it privately for updates; it is Git-ignored. `secrets/` holds local GitHub App credentials and is also Git-ignored. **Never commit either, put secrets in Nix expressions, or copy the key into the Nix store.** Unattended NixOS upgrades are disabled.
