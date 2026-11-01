# Agentic

A composable repository for building and maintaining an agentic machine. It brings together NixOS deployment, Git remote access and protection, sandboxing, and versioned skills. More harnesses and integrations can be added without changing the install/update boundary.

## What is supported today

### 🤖 Agent harnesses

- [Pi](docs/sandbox.md), launched through a nono sandbox wrapper.
- [Oh My Pi](docs/sandbox.md), launched through its own nono sandbox wrapper. Other harnesses can be added later.

### 🔗 Git remotes and safeguards

- **GitHub:** [App-backed access](docs/github-app.md) for MCP reads and Git HTTPS pushes, [branch protection guidance](docs/recommended-rulesets.md), and scheduled read-only constraint audits. Approval-gated merge automation is **not** implemented.

### 🛡️ Sandboxes

- [nono](docs/sandbox.md) profiles for the current harnesses; private GitHub App credentials stay on the host.

### 🧩 Skills

- Reviewed skills under `skills/available/`, including [Matt Pocock's skills](skills/available/mattpocock/IMPORT.md). Checked-in links under `skills/enabled/` select what NixOS installs; see the [decision record](docs/adr/0001-select-skills-with-checked-in-symlinks.md).

### 🖥️ Machine deployment

- [Fresh NixOS installation](docs/install.md) with nixos-anywhere and Disko (**erases the selected disk**).
- [Non-destructive updates](docs/update.md) via NixOS rebuild over SSH (**no Disko**). These workflows are scripted today; the repo structure leaves room for deployment automation.

## Repository map

- `nixos/`: flake, system modules and local nono profiles.
- `scripts/install/`, `scripts/update/`: operator workflows. Both use `scripts/stage.sh` to build credential-free deployment source.
- `scripts/runtime/`, `scripts/github/`, `github-protection/`: host-side GitHub credentials, setup and protection audits.
- `skills/available/`, `skills/enabled/`: versioned skills and the sole installation selection.
- `docs/`: task guides, security guidance, upgrade notes and decisions.

`.deployment/` holds generated machine configuration and the Nix lock file. Keep it privately for updates; it is Git-ignored. `secrets/` holds local GitHub App credentials and is also Git-ignored. **Never commit either, put secrets in Nix expressions, or copy the key into the Nix store.** Unattended NixOS upgrades are disabled.
