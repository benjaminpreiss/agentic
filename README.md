# Agentic — provider-independent NixOS deployment

A reusable NixOS base for dedicated AI coding servers, deployed **from your computer** with [nixos-anywhere](https://github.com/nix-community/nixos-anywhere). The repository contains **no VPS hostname, server IP, disk path, or SSH public key**. A local wizard generates these in `.deployment/` (gitignored).

> **DESTRUCTIVE:** `nixos-anywhere` formats the selected disk. It does not preserve the existing OS, `/home/agentic`, SSH host keys, or local backups. Copy all important data off the server first. Have provider console/recovery access.

## Requirements

- Your computer: Nix with flakes support, Python 3, SSH client, and SSH private key.
- Target: x86_64 Linux, supported kexec environment, reachable over SSH as **root or passwordless-sudo** user.
- An out-of-band recovery console and verified OFF-SERVER backup.
- Full target disk device, boot mode, network interface, and DHCP/static addressing known from the actual target.
- A local SSH public key that will grant access to `agentic` after installation.

## Install

From the repository root on your computer:

```bash
python3 scripts/prepare.py
bash scripts/preflight.sh
bash scripts/deploy.sh --install
```

The preparation wizard asks for SSH target, NixOS hostname, installation disk, UEFI/BIOS mode, SSH key, SSH port, and DHCP/static network settings. It **does not modify the server**. The preflight prints disk and firmware information for manual comparison. The deploy script evaluates the generated flake and requires typing `ERASE-AND-INSTALL-NIXOS` before invoking `nixos-anywhere`.

**Network caution:** The base configuration assumes `systemd-networkd` with a single interface (DHCP by default). Provider-specific networking, static routes, VLANs, IPv6, special virtualization drivers, and DHCP-derived settings may require editing `generated/machine.nix` or a Nix module before installation. Verify provider prerequisites; do not deploy blindly.

After installation, reconnect using your key as `agentic@host` (check the configured SSH port). Only key authentication is enabled; no agent password or sudo is configured.

## What is installed

- NixOS 26.05 channel input (generate `flake.lock` before deploying)
- `agentic` user without sudo; `/home/agentic/work`
- Git, Node.js 24, Zsh, Starship, curl, tmux, Python, terminal utilities
- OpenSSH (key only), Fail2ban, AppArmor, firewall
- `nnpi` wrapper that refuses to run outside `~/work`, without changing directories; `HERDR_AGENT=pi` and `JITI_FS_CACHE=false`
- Once-per-shell welcome message in interactive Zsh
- Root-only compressed home backups, daily at 03:30 + jitter, keeping 14 archives

**Not yet fully provisioned:** Pi, nono, Herdr, Herdr Core (`hc`), Matt Pocock skills, Nix-native GitHub MCP service, and Agenix secrets are intentional follow-up work. The base includes the `nnpi` launcher but it will explain that Pi or nono is not installed until those integrations are deployed. See [postinstall notes](docs/POSTINSTALL.md).

**Automatic OS upgrades:** Not enabled in this initial bundle. A machine-specific, version-locked configuration must first be made available on the machine before safely scheduling `nixos-rebuild`. Initial NixOS upgrades should be applied manually and tested before automation.

## Day-two changes

The generated machine-specific flake is in `.deployment/`. Keep a secure copy of its generated configuration and `flake.lock` somewhere safe; it is excluded from the public repository intentionally. Run a regular `nixos-rebuild switch --flake /path/to/machine-flake#agentic` on the target or deploy the evaluated closure remotely once you have a safe update process. **Never re-run `nixos-anywhere` to apply routine updates.**

## Security notes

A local backup on the install disk is **erased with the old OS**. Clone or archive the old `/home/agentic` onto separate storage before installation. Do not store GitHub App private keys in your public Git repository, the Nix store, or the agent workspace.

## Project files

- `flake.nix` — generic entry point
- `modules/base.nix` — users, SSH, networking, hardening, shell
- `modules/disk.nix` — destructive GPT disk layout, BIOS or UEFI
- `modules/agentic.nix` — workspace, wrapper, status, backup timer
- `scripts/prepare.py` — interactive local configuration generator
- `scripts/preflight.sh` — inspect the remote host before erasing it
- `scripts/deploy.sh` — confirmed `nixos-anywhere` install
- `docs/POSTINSTALL.md` — known gaps and next steps

This project is a **starting point, not a tested universal installer**. Verify `nix flake check`/evaluation and the entire installation in a disposable VM before deploying to a VPS.
