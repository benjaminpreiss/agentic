# Install a new Agentic machine

**This installs NixOS by repartitioning and formatting the selected whole disk. It cannot preserve existing partitions.** Back up data off-server and verify SSH and out-of-band console access before proceeding. For an existing Agentic NixOS machine, use the [non-destructive update](update.md) instead.

From the repository root on a Mac or Linux deployment computer, install `ssh`, `nix` (with flakes), and `nixos-anywhere`. Keep this checkout private; `.deployment/` and `secrets/` are ignored by Git.

## Prepare and inspect

```bash
bash scripts/install/prepare.sh
bash scripts/install/recovery-password.sh
bash scripts/install/preflight.sh
```

Preparation queries the target over SSH, asks for an explicit **whole disk to erase**, network mode, SSH key and boot settings, then stages only the declared NixOS sources. It refuses an existing `.deployment/`. Save that directory privately; do not delete it after deployment. The recovery password is for the provider's console, not SSH. Preflight obtains the hardware report and pins flake dependencies before evaluation.

Check `.deployment/generated/machine.nix`, `.deployment/selected-disk.txt`, `.deployment/target.txt`, and `.deployment/generated/facter.json` against your target. If anything is wrong, stop and correct the preparation before deployment.

## Destructive deployment

**The following command erases the selected disk. Verify backups and disk identity first.**

```bash
bash scripts/install/deploy.sh --install
```

The installer requires `--install` and a final disk confirmation; it invokes nixos-anywhere with Disko. Do not run it to repair or update an installed machine.

## Verify and recover

After boot, confirm SSH as `agentic` and check `journalctl -u agentic-firstboot-check -b --no-pager`, networking, `pi --version`, and `omp --version`. A reinstall changes the SSH host key: verify its new fingerprint through a trusted console before updating `known_hosts`. Test the `recovery` password using the provider's **out-of-band console**. Keep `.deployment/generated/{machine.nix,facter.json}` and `.deployment/flake.lock` for [updates](update.md); retain an off-server backup. If a launcher reports a missing nono pack, use the update workflow, not the disk installer. See [sandbox guidance](sandbox.md) and [GitHub setup](github-app.md).
