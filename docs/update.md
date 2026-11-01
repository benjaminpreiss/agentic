# Update an installed Agentic NixOS machine

Use this workflow only when the machine is already installed and reachable by root SSH. **Never run `scripts/install/deploy.sh --install` to update: it invokes Disko and erases the selected disk.**

## Before switching

Keep the original `.deployment/` directory, especially `generated/machine.nix`, `generated/facter.json`, `flake.lock` and `target.txt`. Confirm `ssh root@YOUR_HOST` and an out-of-band console recovery path. Review source and credentials separately; an off-server backup is recommended.

From the repository root:

```bash
bash scripts/test-stage.sh
bash scripts/github/test-configure-git-credentials.sh
bash scripts/update/apply.sh
```

Apply refreshes all declared NixOS modules, profiles, runtime code, audit code and selected skills through the same staging operation used by install. It leaves generated machine files, recovery password hash and `flake.lock` in place. It evaluates the NixOS system **before** prompting, then switches via remote `nixos-rebuild` without running Disko. Local GitHub App credentials, if configured, are sent separately by SSH to root-owned files outside the flake. After activation, it prepares and verifies nono packs as `agentic`.

## Verify and recover

Reconnect and check `pi --version`, `omp --version`, `systemctl status agentic-backup.timer --no-pager`, and any changed service. See [sandbox use](sandbox.md) and [GitHub setup](github-app.md). If the rebuild fails, preserve the known-good NixOS generation and diagnose the error using the provider console if SSH is unavailable; do not run the fresh installer as a repair step. Server-local backups are not off-server backups. Unattended system upgrades remain disabled.
