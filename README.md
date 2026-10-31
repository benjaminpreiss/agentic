# Agentic NixOS

Provider-independent NixOS deployment using **nixos-anywhere**, **Disko**, and **nixos-facter**, with an SSH-based preparation wizard and a separate workflow for updating an installed machine.

> **Important:** Fresh installation **erases the selected disk**. Copy anything important to another machine first. Never use the fresh-install command to apply ordinary configuration changes.

## Requirements

On your Mac or Linux deployment computer:

- Nix with flakes enabled
- Bash, SSH, and `curl`
- An SSH key authorized on the target

On the *existing* Linux target for a fresh installation:

- SSH access as root or a user with **passwordless sudo**
- A supported `x86_64` machine and a disk you are prepared to erase
- A provider console or independent recovery mechanism

You can download this repository as a GitHub archive; Git does not need to be installed on your deployment computer:

```bash
curl -fsSL -H 'Cache-Control: no-cache, no-store' \
  "https://github.com/benjaminpreiss/agentic/archive/refs/heads/main.tar.gz?t=$(date +%s%N)" \
  | tar -xz
cd agentic-main
```

If `agentic-main` already exists, use a separate empty directory so old files are not mixed with the new download. Review scripts and configuration before executing them.

## Fresh installation (new machine)

### 1. Prepare and discover the server

```bash
bash scripts/prepare.sh
```

The wizard connects to your chosen SSH target and discovers the architecture, available disks, boot mode (BIOS or UEFI), current network details, network interface MAC address, and hostname. It asks you to confirm the **whole disk to erase**, network configuration, and the SSH public key for the installed NixOS system.

Machine-specific files are written into `.deployment/`, which is ignored by Git. **The selected disk will be repartitioned and formatted by Disko.** There is no partition-reuse mode.

If you want to prepare a different machine, back up any needed local deployment settings and move the existing `.deployment/` directory out of the way before running preparation again.

### 2. Configure console recovery

```bash
bash scripts/recovery-password.sh
```

Choose a temporary password for the `recovery` account so you can log in through your provider's console if SSH or networking fails after the first boot. The generated deployment uses a password hash rather than storing the plaintext password in your repository. Keep `.deployment/` private.

### 3. Inspect and validate

```bash
bash scripts/preflight.sh
```

This performs read-only remote checks and evaluates the effective NixOS configuration, including GRUB targets, system assertions, MAC-based network matching, SSH, and static IPv4 values where applicable.

Review the generated settings and chosen disk:

```bash
cat .deployment/generated/machine.nix
cat .deployment/selected-disk.txt
cat .deployment/target.txt
```

A passing preflight is **not** a guarantee of a successful boot or network connection. Verify provider-specific addressing, routes, IPv6 requirements, SSH access, console recovery, and an off-server backup before proceeding. Complex networks may require manual configuration.

### 4. Install NixOS (destructive)

```bash
bash scripts/deploy.sh --install
```

The script repeats preflight and requires you to type `ERASE-AND-INSTALL-NIXOS`. It invokes nixos-anywhere to boot a temporary installer, generate `facter.json`, use Disko to create a fresh disk layout, and install NixOS.

**Do not run this against a machine you want to update in place.**

### 5. Verify the first boot

After installation, confirm that you can connect using the new `agentic` account and the selected SSH key:

```bash
ssh agentic@YOUR_SERVER
```

Then verify basic system health:

```bash
cat /etc/os-release
ip -br address
ip route
systemctl status sshd systemd-networkd --no-pager
journalctl -u agentic-firstboot-check -b --no-pager
```

Also test logging into the provider console as `recovery` with the password chosen above. Keep this recovery path available until remote access has been confirmed stable.

Keep `.deployment/generated/facter.json` and your local lock file with the machine's private deployment records; future rebuilds depend on the same generated machine configuration and hardware report.

## Update an existing Agentic NixOS machine

**Do not rerun `deploy.sh --install`.** For normal configuration updates, use `nixos-rebuild`, which does not erase or repartition the disk.

Make your edits in the repository, then, from the repository root, run:

```bash
bash scripts/apply.sh
```

The helper reuses `.deployment/`, validates the NixOS system derivation, asks for confirmation, and runs a remote `nixos-rebuild switch` on the existing machine. It requires working SSH access and the previously generated local deployment files.

See **[docs/APPLY-EXISTING-NIXOS.md](docs/APPLY-EXISTING-NIXOS.md)** for detailed instructions, assumptions, and recovery notes.

## Repository layout

```text
flake.nix                 NixOS flake
modules/
  base.nix                Base system, networking, SSH, hardening
  disk.nix                Fresh BIOS/UEFI disk layout via Disko
  agentic.nix             Agent user, shell, workspace, dashboard, backups
  recovery.nix            Console recovery account
  firstboot.nix           First-boot diagnostic service
scripts/
  prepare.sh              SSH discovery and machine-specific generation
  recovery-password.sh    Interactive console recovery credential setup
  preflight.sh            Read-only pre-installation validation
  deploy.sh               Destructive fresh installation
  apply.sh                Non-destructive configuration update
 docs/
  APPLY-EXISTING-NIXOS.md  Updating a running NixOS machine
  POSTINSTALL.md          Post-installation checks and future integrations
.deployment/              Generated per-machine files (not committed)
```

## Current capabilities and limitations

The current NixOS bundle defines the `agentic` user and `~/work`, Zsh and Starship, Ghostty terminfo, SSH and MAC-based networking, basic OS hardening, firewall configuration, a terminal status screen, a console recovery user, first-boot diagnostics, and local home-directory backups (14-archive retention).

Pi, nono, Herdr, skills, GitHub MCP/App authentication, and GitHub App-backed Git HTTPS credentials are declared in the NixOS modules. Git push requires deploying those modules and App credentials; see `AGENTIC_GITHUB_SETUP.md` for setup and verification. Unattended NixOS system upgrades remain disabled. Do not assume feature parity with the earlier Ubuntu `nnpi.sh`.

The backup archives live on the same server and are **not** a substitute for off-server backups. The flake and hardware/network setup still need end-to-end testing for each target environment.

## Safety principles

- Use `prepare.sh` + `preflight.sh` + `deploy.sh --install` **only for fresh installs**.
- Use `apply.sh` **only for an already-running NixOS machine**.
- Check the whole-disk target before confirming installation.
- Never commit private keys, recovery credentials or `.deployment/`.
- Verify network access and console recovery after every fresh installation.
- Preserve the known-good NixOS generation when troubleshooting rebuild failures; do not repartition as a repair step.
