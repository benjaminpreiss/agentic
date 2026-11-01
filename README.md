# Agentic NixOS

Deploy a sandboxed Pi and Oh My Pi workstation with NixOS. **Installing erases a disk; updating an installed machine does not.** Start with the guide for your task:

- [Install a new machine](docs/install.md) — discovery, disk confirmation, recovery password and destructive deployment.
- [Update an installed machine](docs/update.md) — refresh staged sources and switch NixOS over SSH, without Disko.
- [Use sandboxed agents and select skills](docs/sandbox.md).
- [Configure GitHub App access](docs/github-app.md).

## Where things live

`nixos/` holds the flake, modules and nono profiles. `scripts/install/` and `scripts/update/` are the operator workflows; both call `scripts/stage.sh` to prepare a credential-free flake source. `scripts/runtime/` supplies host-side credential code. `scripts/github/` and `github-protection/` contain GitHub setup and audit code. `skills/available/` contains versioned skills; checked-in links in `skills/enabled/` are the only selection interface. See [the skills decision](docs/adr/0001-select-skills-with-checked-in-symlinks.md).

`.deployment/` contains machine-specific configuration and the lock file; retain it privately for future updates. `secrets/` contains local GitHub App credentials; **neither directory belongs in Git history.** Only explicit, credential-free sources are copied into the staged flake. Do not put secrets in Nix expressions or the Nix store.

No production deployment is performed by this repository checkout alone. Unattended NixOS upgrades are disabled.
