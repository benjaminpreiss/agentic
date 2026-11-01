# Update an existing Agentic NixOS machine

Use `scripts/apply.sh` for an **already installed, SSH-reachable NixOS machine**. Do **not** rerun `scripts/deploy.sh --install`: the Disko installation command erases the selected disk.

## Before applying

- Keep the working `.deployment/` directory, including `generated/machine.nix`, `generated/facter.json`, and `flake.lock`. The machine configuration records your disk, boot mode, MAC-based network settings, and SSH key.
- Confirm that SSH to `root@YOUR_HOST` still works and that you have a provider-console recovery path.
- Review your source changes and any credentials separately. `scripts/apply.sh` evaluates the system before asking for confirmation; it does not repartition or format disks.

From the repository root on your deployment computer:

```bash
bash scripts/apply.sh
```

The helper refreshes its selected NixOS modules, flake, runtime scripts, and nono profiles in `.deployment/`, evaluates the system, prompts for confirmation, and runs a remote `nixos-rebuild switch`. Review the files it copies when adding new modules or scripts; this is not yet a complete source sync. If local GitHub App credentials are present in `secrets/github-app/`, they are transmitted separately over SSH to root-owned files on the target; they are never added to the Nix flake source. After activation, the helper prepares and verifies the nono packs and profiles as `agentic`.

Reconnect as `agentic` and check the updated services and sandboxed tools:

```bash
ssh agentic@YOUR_HOST
cd ~/work
pi --version
omp --version
systemctl status agentic-backup.timer --no-pager
```

The installed `pi` and `omp` commands are nono sandbox launchers; see [SANDBOXED-AGENTS.md](SANDBOXED-AGENTS.md). For GitHub App configuration and verification, see [the GitHub setup guide](../AGENTIC_GITHUB_SETUP.md).

If the rebuild fails, preserve the known-good NixOS generation and investigate the failure. Do not run the fresh installer as a repair step. Backups are **local to the server**, not a substitute for off-server backups. Unattended NixOS system upgrades are disabled.
