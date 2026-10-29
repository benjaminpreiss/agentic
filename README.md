# Agentic — provider-independent NixOS deployment

**Experimental deployment bundle. Do not deploy onto a server you cannot afford to erase until the NixOS evaluation, boot and networking have been tested.** `nixos-anywhere` **destroys the selected disk**. Back up `/home/agentic` **off-server**; any on-disk backups are also lost.

## Overview

- `nixos-facter` provides the hardware report during installation, rather than custom kernel-module discovery.
- `disko` defines GPT partitions and root filesystem; the wizard selects a **whole disk** and confirms BIOS versus UEFI.
- `nixos-anywhere` installs NixOS remotely.
- `scripts/prepare.sh` inspects the existing Linux server using **read-only SSH commands**, suggests settings, asks for confirmation, and generates private `.deployment/` files.
- `scripts/preflight.sh` verifies that the machine still matches the generated settings and evaluates the NixOS configuration.
- `scripts/deploy.sh --install` demands explicit destructive confirmation.

No provider-specific IP, disk, hostname or SSH key is hardcoded. Neither Git nor Python is required for the **Bash wizard** on the Mac, although Nix may internally fetch sources using its own mechanisms.

## Prerequisites

Your computer: Nix with flakes enabled, Bash, SSH, curl. Remote target: running Linux, SSH access as root **or a user with passwordless sudo**, `lsblk`, `ip`, `findmnt`, `networkctl` (optional). If a package is missing on the remote host, install it before running discovery.

Your local SSH key must be ready for use. An emergency provider console or rescue image is strongly recommended.

## Run

```sh
bash scripts/prepare.sh
bash scripts/preflight.sh
# STOP: verify off-server backups, the selected disk, connectivity, and rescue access.
bash scripts/deploy.sh --install
```

The generated configuration is in `.deployment/`, excluded from Git, and includes `generated/machine.nix` and (after installing) `generated/facter.json`. The installer may generate a lock file there: retain it for reproducibility and move it into your managed host configuration later.

The installer will explicitly ask you to approve the target disk. This is **not** an in-place migration.

## What discovery does and doesn't do

Auto-detected and then confirmed: CPU architecture, hostname, boot mode, likely root disk, network interface, IPv4 address, default route, and likely DHCP mode. It asks you to select the public SSH key and approve the target disk. Hardware drivers are selected by `nixos-facter` in the installer.

**Network caveat:** It does not automatically translate complex cloud networking (e.g. IPv6-only hosts, additional IPv6 addresses, off-link gateways, routes, bonds, VLANs, policy routing, special DHCP routes). If your target uses these, **do not deploy until you have edited and evaluated `generated/machine.nix` and/or `modules/base.nix`**. The wizard defaults to static networking when it cannot find affirmative DHCP evidence. Never assume Ubuntu's interface name stays identical after a NixOS installation.

**Disk caveat:** A discovered root parent is a suggestion, not a safe automatic selection. Storage using LVM/RAID/encryption and multiple disks may need manual planning.

## What is currently configured

NixOS base: `agentic` user (no sudo), key-only SSH, UFW-equivalent firewall, fail2ban, Zsh/Starship, a limited hardening baseline, and a local `~/work` directory. `nnpi` is a placeholder wrapper that requires nono and Pi to be installed (see `docs/POSTINSTALL.md`). A daily timer creates root-only compressed home backups and retains fourteen. **There is no automated NixOS rebuild and no configured GitHub MCP yet.**

The current bundle **does not yet have feature parity** with the original Ubuntu `nnpi.sh`. Pi, nono, Herdr/`hc`, Matt Pocock skills, and the secure GitHub App MCP integration remain post-install work. Do not destroy a production installation expecting those features to be working immediately.

## Files

- `flake.nix`: NixOS flake using nixpkgs and disko.
- `modules/base.nix`: operating system, users, SSH, network and hardening.
- `modules/disk.nix`: BIOS/UEFI conditional disko partitioning and bootloader.
- `modules/agentic.nix`: shell, wrapper and backup timer.
- `scripts/prepare.sh`: read-only SSH discovery and interactive generation.
- `scripts/preflight.sh`: reconfirm machine and evaluate flake.
- `scripts/deploy.sh`: destructive confirmation and `nixos-anywhere` with facter generation.
- `docs/POSTINSTALL.md`: limitations and further setup.

## References

- [nixos-anywhere quickstart](https://github.com/nix-community/nixos-anywhere/blob/main/docs/quickstart.md)
- [nixos-anywhere reference](https://github.com/nix-community/nixos-anywhere/blob/main/docs/reference.md)
- [disko](https://github.com/nix-community/disko)
