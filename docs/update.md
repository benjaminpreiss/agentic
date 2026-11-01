# Update an existing Agentic NixOS machine

Use this guide only for a machine already installed and reachable by root SSH. **Do not rerun `scripts/install/deploy.sh --install`: it invokes Disko and erases the selected disk.** `scripts/update/apply.sh` evaluates, confirms and switches an existing installation without repartitioning.

## 1. Update the local repository

On the deployment computer, use the **same checkout** that contains the machine's `.deployment/`. If it is a Git checkout tracking `main`, review your changes and update it with a fast-forward only:

```bash
git status --short
git switch main
git pull --ff-only origin main
```

Stop if Git reports local conflicts, a non-fast-forward history, or uncommitted changes you have not reviewed. Do **not** reset, clean or delete `.deployment/` to make the pull work. If this is an archive rather than a Git checkout, obtain the new source without replacing or discarding the private `.deployment/` and `secrets/` directories; verify they remain in this checkout before applying. `git pull` changes tracked code, not Git-ignored machine records.

## 2. Check the machine and private deployment state

Confirm root SSH and your provider's out-of-band console still work. Keep an off-server backup. Check that the existing deployment is intact:

```bash
ls -l .deployment/flake.lock .deployment/generated/machine.nix \
  .deployment/generated/facter.json .deployment/target.txt
cat .deployment/target.txt
```

The generated machine configuration, hardware report, lock file, recovery password hash and target belong to this machine; **do not replace them with files from another machine**. If any are missing, recover the original `.deployment/` backup before updating. Review local changes to credentials separately; [GitHub App credentials](github-app.md) are uploaded via SSH, never copied into the flake.

## 3. Run local checks

From the repository root:

```bash
bash scripts/test-stage.sh
bash scripts/github/test-configure-git-credentials.sh
```

Stop if either test fails. Both installation and update use `scripts/stage.sh` to refresh declared, credential-free modules, runtime code, profiles, audit code and selected skills. Staging leaves machine-specific files and `flake.lock` untouched; it is not a copy of the whole repository.

## 4. Evaluate and switch — no disk formatting

```bash
bash scripts/update/apply.sh
```

The script stages sources and evaluates the complete NixOS derivation **before** asking for confirmation. Review any failure rather than falling back to the installer. If you confirm, it uploads configured GitHub App credentials separately, runs remote `nixos-rebuild switch`, and then prepares and verifies nono packs. No Disko command is run.

## 5. Verify and recover

Reconnect as `agentic`, then check the commands and services relevant to your change:

```bash
cd ~/work
pi --version
omp --version
systemctl status agentic-backup.timer agentic-skills.service --no-pager
```

If upgrading from a version before PR #28, read the [PR #28 upgrade notes](skills-migration.md): the old Matt Pocock skills link is **not** removed automatically. Check [sandbox and skills](sandbox.md) and [GitHub setup](github-app.md) for feature-specific verification.

If evaluation fails, no switch has occurred. If switching fails, preserve the known-good NixOS generation and diagnose via SSH or the provider console; **never run the disk installer as a repair step**. Server-local backups are not off-server backups. Unattended system upgrades remain disabled.
