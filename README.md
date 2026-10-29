# Agentic NixOS — safe fresh installation

This bundle prepares a fresh NixOS install with Disko, nixos-facter and nixos-anywhere. **It erases the chosen disk.** Verify off-server backups and a console before deployment.

## Setup (Mac/Linux)

```bash
bash scripts/prepare.sh
bash scripts/recovery-password.sh
bash scripts/preflight.sh
bash scripts/deploy.sh --install
```

The wizard discovers the default-route interface's MAC and generates `matchConfig.MACAddress` instead of assuming Ubuntu and NixOS use the same NIC name. The generated network settings remain local in `.deployment/`.

The recovery script asks for a console password and saves **only a salted hash** to `.deployment/extra-files/etc/agentic/recovery-password-hash` (mode 0600). `nixos-anywhere --extra-files` copies this into the installed system. The secret is not imported into the Nix store. The temporary `recovery` account is a sudo-capable **console** user; SSH password authentication remains disabled. Protect the local `.deployment/` directory and delete the local hash when no longer needed.

On first boot, open the provider console and test logging in as `recovery`. First-boot diagnostics are printed to the console and journal:

```bash
journalctl -u agentic-firstboot-check --no-pager
ip -br addr
ip route
networkctl status
systemctl status sshd
```

Once SSH access and networking are verified, remove the recovery account/module and its secret through a tested `nixos-rebuild switch`. Do not remove console recovery before testing SSH.

## Changes compared to previous bundle

- `scripts/prepare.sh`: MAC discovery and generation
- `scripts/preflight.sh`: MAC and effective network assertions, recovery secret presence
- `scripts/deploy.sh`: install-only `--extra-files` for console recovery hash
- `scripts/recovery-password.sh`: **new** interactive password hash helper
- `modules/base.nix`: MAC-based match, updated DHCP config
- `modules/recovery.nix`: **new** console recovery account
- `modules/firstboot.nix`: **new** diagnostic service
- `flake.nix`: imports new modules
- `modules/disk.nix`: includes the duplicate-GRUB-device fix

**Important:** This bundle has not undergone a full Nix evaluation or remote boot test. It is a recovery-oriented update to the earlier proof of concept, not a production-tested installer. The source is installed using the local generated `.deployment/` flake. Do not run against an unreachable or already-installed machine without a recovery plan.
