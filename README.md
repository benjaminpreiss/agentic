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

- Reviewed skills under `skills/available/`, including [Matt Pocock's skills](skills/available/mattpocock/IMPORT.md). The checked-in, symlink-free [`skills/enabled.nix`](skills/enabled.nix) selects what NixOS installs, including recursive family selections; see [choosing skills](docs/skills.md).

### 🖥️ Machine deployment

- [Fresh NixOS installation](docs/install.md) via the pinned `moss machine plan → apply → bootstrap` CLI (**`apply` erases the selected disk only after typed confirmation**).
- [Non-destructive updates](docs/update.md): toolkit-managed hosts poll their operator-selected branch or stay pinned to a commit (**no Disko**). Existing hosts retain the manual SSH update until individually migrated.

## Repository map

- `flake.nix`, `flake.lock`, `deployment/`: reviewed toolkit-managed flake, dependency pins and agentic-specific modules.
- `nixos/`, `scripts/update/`, `scripts/stage.sh`: temporary legacy manual update path for existing hosts; do not remove before migration. `scripts/install/recovery-password.sh` only prepares a new host's private recovery hash.
- `scripts/deployment/`: thin pinned `moss` CLI invoker, agentic-specific machine preparation and evaluated install hooks.
- `scripts/runtime/`, `scripts/github/`, `github-protection/`: host-side GitHub credentials, setup and protection audits.
- `skills/available/`, `skills/enabled.nix`: versioned skills and their reviewed selection.
- `docs/`: task guides, security guidance, upgrade notes and decisions.

`.moss/` holds ignored operator-local machine configurations, plans and receipts; `.deployment/` holds private machine facts and (for existing hosts only) their original lockfile. Back both up off-host and never commit them. New hosts use the committed root lockfile. `secrets/` holds local GitHub App credentials and is Git-ignored. **Never put private keys, hashes or tokens in Nix source or the store.** Only hosts explicitly bootstrapped and switched to branch tracking perform autonomous OS updates.
