# Draft: Agentic on openSUSE Tumbleweed (NOT an installer)

This is an **incomplete, non-deployable Agentic prototype** to explore independently authored modules, dependency ordering and Ansible introduction scripts. The supported deployment remains [NixOS](../../docs/install.md). Do not run this on a production server. There is no disk installer, driver removal, Nix bootstrap or full Agentic setup here.

## Experiment boundary

- Start from a **fresh, disposable x86_64 openSUSE Tumbleweed VM** installed using an official image with working console recovery. Never convert the existing Agentic host or use the NixOS disk-erasing installer against this VM.
- Tumbleweed is the base substrate; Nix (eventually) supplies pinned Agentic software, not OS configuration. The existing NixOS modules **cannot** be used as-is on Tumbleweed.
- Every `modules/<id>/module.json` declares the versioned interface it `implements`, its public operation-to-script mapping (`provides`), a zero-argument `entrypoint`, and `requires_interfaces` rather than concrete module dependencies. Its `introduce.yml` implements its entrypoint. The hardware module also owns `measure.sh`. The OS prerequisite, read-only measurement and **partial** base-access introduction can currently run as a chain. The backup module has a concrete, untested introduction script but depends on Agentic harness setup, which is blocked. Other modules' scripts explicitly fail closed rather than claim successful installation. These mark missing transitions, not implemented modules.
- `plan.py` orders declarations and rejects missing dependencies, missing scripts and cycles. It binds versioned interfaces to providers, checks method signatures, and emits an Ansible playbook. It does **not** determine live state, manage instances/secrets, apply migrations, or infer success from a generated plan.
- `modules/hardware-inventory/measure.sh` is a **read-only** hardware/boot/service inventory on the Tumbleweed VM. Save its output privately, e.g. `bash modules/hardware-inventory/measure.sh > private-hardware-report.txt` outside Git. Ansible suppresses its output to avoid leaking machine details to logs. It does not establish which drivers can be removed.

From the repository root, run `python3 experimental/tumbleweed/plan.py` and `python3 -m unittest discover -s experimental/tumbleweed -p 'test_*.py'`.

To try **only the implemented partial chain** on a fresh VM, create a private Ansible inventory with an `agentic_vm` host and SSH access. Then:

```bash
cd experimental/tumbleweed
python3 plan.py --until base-access > introduction.generated.yml
ansible-playbook -i /private/path/to/inventory.ini introduction.generated.yml \
  -e agentic_disposable_vm=true -e agentic_console_verified=true
```

Confirm both assertions in reality before setting them; do not use them to bypass recovery checks. The playbook uses privilege escalation and changes packages on the target. `introduction.generated.yml` must stay local (Git-ignored), since an inventory or Ansible output can contain private target details. Running `python3 plan.py --playbook > introduction.generated.yml` plans **all** modules, but currently stops deliberately at Nix bootstrap. Ansible is not installed in this development environment, so no syntax check or VM run has been completed.

## Interfaces: modules as small objects, not Ansible roles as API

**Every module in this prototype is an implementation of a versioned interface** in `interfaces/`. A module requires interfaces, never concrete module IDs; its `substrate` is also an interface requirement (except the native OS root). `bindings.json` selects one provider for each interface. The planner validates that each provider implements its bound interface, that its entrypoint is a zero-argument operation, and that every call matches the declared signature. It visits required providers before the caller, then emits the bound Ansible tasks. No caller imports another module's scripts directly.

Most interfaces currently expose only `ensure()` as their entrypoint; this is the **shape of the contract**, not proof that the operation fulfills it. The current fail-closed Ansible scripts still block full installation. An interface version expresses method names and argument types, not a verified semantic or operational postcondition. Future migrations and verification must address that gap.

`interfaces/timer.v1.json` is a richer example: `prepare()`, `ensure(id, command, schedule)` and `remove(id)`. `modules/systemd-timer/` provides these using systemd units. `bindings.json` selects `systemd-timer` for `timer@1`. `home-backup/module.json` requires `timer@1` and calls `ensure`; its own `ensure()` only installs the archive program. The planner validates the call and emits Ansible `include_tasks` **after** the executable is installed. No systemd syntax or timer-unit paths remain in the backup module. A different provider could satisfy the same signature, but live-state migration between providers is *not* implemented.

`timer@1` is intentionally narrow: a **root-owned, system-wide, calendar-triggered one-shot command**. It is not a general runner for arbitrary Ansible tasks or a universal scheduler. The provider refuses to overwrite a pre-existing unmanaged timer/service ID. The inverse `remove` operation refuses to delete unmanaged units, but module removal orchestration has not been implemented; do not invoke it as a general cleanup script. Contract checks only prove argument *shape*, not semantic equivalence or safe scheduling.

This does **not require abandoning Ansible**. Ansible executes the provider's private tasks; the planner owns dependency binding and interface validation. Replacing Ansible would only become necessary if its task execution model prevents essential transitions or verification on a real VM. Ansible and the generated playbook have not been run on Tumbleweed yet.

## Scope mapped from the current deployment

| Proposed module | Existing source | Status / missing introduction |
|---|---|---|
| opensuse-tumbleweed | `nixos/flake.nix`, `nixos/modules/disk.nix` | Verifies external fresh VM image; image pinning and disk/boot workflow not implemented |
| hardware-inventory | `nixos/modules/base.nix` | Read-only measurement task implemented; no driver/service reduction yet |
| base-access | `nixos/modules/base.nix`, `recovery.nix` | Basic tools installed after console confirmation; SSH keys/network/firewall, AppArmor, fail2ban and recovery configuration still pending |
| nix-packages | `nixos/flake.nix` | Nix bootstrap and pinning Pi/OMP/nono/Herdr/tooling need implementation |
| agent-harnesses | `nixos/modules/agentic.nix` | User, workspace, Zsh/Starship, terminfo, status screen and safe Pi/OMP launchers need implementation |
| sandbox | `nixos/modules/agentic.nix`, `nixos/profiles/` | Profiles, sockets and Herdr/nono boundary need porting and verification |
| skills | `skills/enabled/`, `nixos/modules/agentic.nix` | Versioned links and ownership checks need implementation |
| github-integration | `nixos/modules/github-mcp.nix`, `scripts/runtime/`, `github-protection/` | App key outside sandbox, MCP, credential broker, Git helper, audit timer need implementation; never place PEM in Nix store |
| systemd-timer | Tumbleweed systemd | Implements `timer@1` behind private systemd templates; untested on VM |
| home-backup | `nixos/modules/agentic.nix` | Uses `timer@1` to schedule its local archive; untested, restore test and off-host backup still required |
| firstboot-diagnostics | `nixos/modules/firstboot.nix` | SSH/network verification and console check need implementation |

## Why the reduction step is blocked

A snapshot of loaded modules is **not** the set of modules needed to boot: the initramfs, storage and networking paths, offline recovery, or future hardware may require modules that are currently unloaded. Tumbleweed's kernel modules are commonly packaged together; removing `kernel-default` is not equivalent to removing unused drivers. The measurement is only input to an operator-reviewed proposal, not permission to trim a kernel or firmware. Before implementing an apply phase we need a target-specific allowlist, a tested console/recovery image, and repeated boot/SSH checks. Any reduction script must show a diff and require confirmation before touching the VM; a failed reboot must be recoverable without SSH.

## Model questions this exposes

- A dependency on `opensuse-tumbleweed` does not imply the required SSH or socket is *ready*. Modules need verifiable conditions and postconditions, not just ordered execution.
- An installed Nix package does not mean its systemd service is serving; installation and operational conditions differ.
- A future migration must verify the source installation and its managed resources; a prior script's exit code alone is insufficient.
- Hardware-specific reduction is not a globally shareable recipe without an explicit machine identity and an operator-approved safety policy.

**Next milestone for this draft:** on a disposable VM, pin the image and Nix inputs, introduce one end-to-end module (including verification and a rerun), measure before/after, and only then port the rest. This PR is intentionally draft until full parity and recovery are tested.
