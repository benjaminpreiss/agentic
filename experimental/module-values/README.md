# Experiment: bound substrate methods (no Ansible)

**Independent draft**, not an Agentic installer or a replacement for the supported NixOS deployment. Use only on a freshly installed **disposable Tumbleweed VM**, with out-of-band console access. This experiment installs Zsh and may create an unprivileged account. It does not set up networking, SSH, passwords, sandboxes or agent harnesses.

## Model

- `os@1` is a general OS substrate preparation interface. The `opensuse-tumbleweed` module implements it; `host` is an **instance** of that module.
- The *same host instance* also provides `login-shell-host@1` and `local-account-host@1`. These conceptual interfaces promise **supported login-shell** provisioning via pure `path_for(shell_id)` and effectful `ensure(shell_id, path)`, and local account provisioning, respectively. An unsupported shell fails during expansion. The Tumbleweed implementation owns the `zypper`, `/etc/shells`, NSS, and `useradd` details. Other substrates can implement the same interfaces with different scripts and path declarations, or decline to implement them; no distro-name constraint is needed.
- The generic `zsh` module implements `login-shell@1`. It owns the choice `shell_id=zsh`, gets its pure `path` from the bound host's `path_for("zsh")`, and delegates `ensure` to that host's `ensure("zsh", path)` transition. The path is declared in the Tumbleweed **module**, not in the interface.
- The generic `local-account` module implements `account@1`. Its instance provides `account_name`, binds to a `login-shell@1` instance for the path and calls the bound `local-account-host@1.ensure_account(name, path)` transition.

`plan.py --expand` is **pure**: it resolves the path `/usr/bin/zsh` and the provider method calls, type-checks values and bindings, and orders host, Zsh, account. It does not contact the target. `plan.py --script` embeds the **bound host implementation's** scripts into a standalone shell script; the planner contains no OS-specific package or account logic, and Ansible is not used. This is a tiny executor, not a general-purpose configuration engine. Runtime checks establish whether the static declaration actually holds; they never supply the declaration's path.

## Inspect without a target

From the repository root:

```bash
python3 -m unittest discover -s experimental/module-values -p 'test_*.py'
python3 experimental/module-values/plan.py --expand
cd experimental/module-values
python3 plan.py --script > introduction.generated.sh
sh -n introduction.generated.sh
```

## Running on a disposable VM (NOT YET VALIDATED)

Review the generated script, take a VM snapshot and confirm out-of-band console access. **Do not run this on the development host.** From `experimental/module-values`, using an SSH account with `sudo` on the disposable VM:

```bash
ssh -T -i /private/path/to/key vm-user@disposable-vm \
  'sudo env AGENTIC_DISPOSABLE_VM=true AGENTIC_CONSOLE_VERIFIED=true sh -s' \
  < introduction.generated.sh
```

The flags confirm *your* verification of disposability and console access; the script cannot prove either. Its first action checks OS identity before installing Zsh or creating the account. Rerunning should preserve an existing matching account; an existing different shell requires an explicit migration. The shell transport itself is not implemented by the planner. No VM execution or distribution-specific package verification has occurred.

## Limits

The interfaces' written guarantees still need real target-side testing, especially `/usr/bin/zsh` registration in `/etc/shells` on Tumbleweed. The planner validates the shape of provider methods but cannot prove shell scripts fulfill their guarantees. Generated scripts and inventory/SSH credentials must not be committed. Provider changes, drift, interruption, password management and account migrations are out of scope. No unsupported NixOS behaviour has changed.
