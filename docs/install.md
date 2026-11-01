# Install Agentic NixOS on a new machine

Use this guide to replace the operating system on a remote machine. **Installation repartitions and formats the selected entire disk. Existing partitions and on-disk backups will be lost.** For a machine already running Agentic NixOS, use the [update guide](update.md) instead.

## 1. Check prerequisites

On your Mac or Linux deployment computer, use this repository checkout with Bash, SSH and Nix with flakes enabled. Have the target's SSH address, a local public SSH key and a provider console ready. The target must be reachable by SSH with root or passwordless sudo; the installer uses `nixos-anywhere`. Back up all data **off the target** and verify that you can recover it. Keep this checkout private: `.deployment/` will contain machine settings and a password hash, and `secrets/` may contain private keys. Both are Git-ignored.

## 2. Discover the target and select the disk

From the repository root, run:

```bash
bash scripts/install/prepare.sh
```

The interactive discovery queries the machine, asks you to choose a **whole disk to erase**, and confirms boot mode, network settings and SSH key. It refuses to replace an existing `.deployment/`. It does **not** format the disk. For a different target, back up your existing `.deployment/` separately before preparing again.

Review the result **before continuing**:

```bash
cat .deployment/target.txt .deployment/selected-disk.txt
cat .deployment/generated/machine.nix
```

Confirm the host, disk, boot and network values match the intended machine. If any value is wrong, stop; do not proceed to installation.

## 3. Set a console recovery password

```bash
bash scripts/install/recovery-password.sh
```

Enter a temporary password for the `recovery` account at the prompt. The command saves only a password hash under `.deployment/extra-files/`, not plaintext. Protect that directory. The recovery account is for the provider's **out-of-band console**, not SSH password login.

## 4. Run preflight checks

```bash
bash scripts/install/preflight.sh
```

Preflight rechecks the remote whole disk, boot mode, network interface and MAC address. It pins flake inputs, evaluates the NixOS derivation and verifies the effective bootloader and network configuration. Review its output, especially the disk and network choices. For static networking, IPv6 or provider-specific routing, independently confirm the configuration. Preflight does not format the disk.

## 5. Deploy — destructive

**Stop unless off-server backups, out-of-band recovery access and the selected disk are verified. The next command invokes Disko and erases that disk.**

```bash
bash scripts/install/deploy.sh --install
```

The installer reruns preflight and requires you to type `ERASE-AND-INSTALL-NIXOS` at the final prompt. It then calls `nixos-anywhere`. Do not use this command for updates or repairs.

## 6. Verify the first boot

1. If the machine was reinstalled, verify its **new SSH host-key fingerprint through the provider console** before updating `known_hosts`. Confirm you can connect as `agentic` with your key.
2. On the machine, run `journalctl -u agentic-firstboot-check -b --no-pager`; check networking and SSH. From `~/work`, test `pi --version` and `omp --version`.
3. Test the `recovery` account password at the provider's out-of-band console. Keep that path available until networking is stable.
4. Keep `.deployment/generated/machine.nix`, `.deployment/generated/facter.json`, `.deployment/flake.lock` and the rest of `.deployment/` privately on the deployment computer for [future updates](update.md). Back them up off-server.

If a launcher reports a missing nono pack, use the [non-destructive update](update.md), not the installer. See [sandbox and skills](sandbox.md) or [GitHub setup](github-app.md) for next steps.
