# Draft: Agentic on openSUSE Tumbleweed (NOT an installer)

This is an **incomplete, non-deployable prototype** to explore whether an Agentic installation can be described as independently authored modules with dependencies and scripts. The supported deployment remains [NixOS](../../docs/install.md). Do not run this on a production server. No disk installer, OS stripping, Nix bootstrap, or Agentic setup is implemented here.

## Experiment boundary

- Start from a **fresh, disposable x86_64 openSUSE Tumbleweed VM** installed using an official image with working console recovery. Never convert the existing Agentic host or use the NixOS disk-erasing installer against this VM.
- Tumbleweed is the base substrate; Nix (eventually) supplies pinned Agentic software, not OS configuration. The existing NixOS modules **cannot** be used as-is on Tumbleweed.
- `modules/*.json` inventories the **full current Agentic scope** with explicit dependency edges and honest implementation statuses. `plan.py` orders them and rejects missing dependencies or cycles. It does **not** install or verify modules, resolve instances, manage secrets, or infer state from a successful plan.
- `measure.sh` is a **read-only** hardware/boot/service inventory run on the Tumbleweed VM. Save its output privately, e.g. `bash measure.sh > private-hardware-report.txt` outside Git. It does not conclude which drivers are safe to remove.

Run locally: `python3 experimental/tumbleweed/plan.py` and `python3 -m unittest discover -s experimental/tumbleweed -p 'test_*.py'`.

## Scope mapped from the current deployment

| Proposed module | Existing source | Status / missing introduction |
|---|---|---|
| opensuse-tumbleweed | `nixos/flake.nix`, `nixos/modules/disk.nix` | Fresh VM image is external; image pinning and disk/boot workflow not implemented |
| hardware-inventory | `nixos/modules/base.nix` | Read-only report implemented; no driver/service reduction yet |
| base-access | `nixos/modules/base.nix`, `recovery.nix` | SSH keys/network/firewall, AppArmor, fail2ban, recovery console need implementation |
| nix-packages | `nixos/flake.nix` | Nix bootstrap and pinning Pi/OMP/nono/Herdr/tooling need implementation |
| agent-harnesses | `nixos/modules/agentic.nix` | User, workspace, Zsh/Starship, terminfo, status screen and safe Pi/OMP launchers need implementation |
| sandbox | `nixos/modules/agentic.nix`, `nixos/profiles/` | Profiles, sockets and Herdr/nono boundary need porting and verification |
| skills | `skills/enabled/`, `nixos/modules/agentic.nix` | Versioned links and ownership checks need implementation |
| github-integration | `nixos/modules/github-mcp.nix`, `scripts/runtime/`, `github-protection/` | App key outside sandbox, MCP, credential broker, Git helper, audit timer need implementation; never place PEM in Nix store |
| home-backup | `nixos/modules/agentic.nix` | Local backup timer/retention need implementation; off-host backups still required |
| firstboot-diagnostics | `nixos/modules/firstboot.nix` | SSH/network verification and console check need implementation |

## Why the reduction step is blocked

A snapshot of loaded modules is **not** the set of modules needed to boot: the initramfs, storage and networking paths, offline recovery, or future hardware may require modules that are currently unloaded. Tumbleweed's kernel modules are commonly packaged together; removing `kernel-default` is not equivalent to removing unused drivers. The measurement is only input to an operator-reviewed proposal, not permission to trim a kernel or firmware. Before implementing an apply phase we need a target-specific allowlist, a tested console/recovery image, and repeated boot/SSH checks. Any reduction script must show a diff and require confirmation before touching the VM; a failed reboot must be recoverable without SSH.

## Model questions this exposes

- A dependency on `opensuse-tumbleweed` does not imply the required SSH or socket is *ready*. Modules need verifiable conditions and postconditions, not just ordered execution.
- An installed Nix package does not mean its systemd service is serving; installation and operational conditions differ.
- A future migration must verify the source installation and its managed resources; a prior script's exit code alone is insufficient.
- Hardware-specific reduction is not a globally shareable recipe without an explicit machine identity and an operator-approved safety policy.

**Next milestone for this draft:** on a disposable VM, pin the image and Nix inputs, introduce one end-to-end module (including verification and a rerun), measure before/after, and only then port the rest. This PR is intentionally draft until full parity and recovery are tested.
