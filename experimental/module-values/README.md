# Experiment: interfaces, modules and instances

**Independent draft**, not an Agentic installer or replacement for the supported NixOS deployment. Use only on a freshly installed **disposable Tumbleweed VM** with out-of-band console access. This experiment installs Zsh and may create a local account; it does not configure networking, SSH, passwords, sandboxes or agent harnesses.

## Model

An **interface** describes a concept and its guarantees, not an OS or an implementation technique:

- `os@1`: an OS substrate whose preparation and recovery preconditions can be checked.
- `login-shell@1`: one configured login shell, with a pure, no-argument `path()` and an effectful `ensure()`.
- `account@1`: one configured local account, with an effectful `ensure()`.

Each **module** implements one interface. `opensuse-tumbleweed` implements `os@1`; `zsh-on-tumbleweed` implements `login-shell@1` and declares `path() = /usr/bin/zsh`; `tumbleweed-local-account` implements `account@1` without hard-coding `agentic` or a shell path. Modules own their scripts, package names, OS checks, and path layouts; neither Ansible nor an extra `*-host` interface is needed. The `script_args` field is a private implementation-to-script mapping, not an interface method argument.

**Instances** select and configure these modules within this deployment: `host` selects openSUSE Tumbleweed, `interactive` selects Zsh and binds `os@1` to `host`, and `agentic` selects the account module, binds `os@1` to `host` and `login-shell@1` to `interactive`, and sets `account_name=agentic`. During **pure expansion**, the account calls its bound `interactive.path()`—no shell selector and no target contact. Then the generated script runs the modules' own `ensure()` implementations in dependency order; they check the declared state on the target instead of discovering values for substitution.

This simplification **does not** claim that rebinding `host` alone makes Tumbleweed-specific shell and account modules portable. Another OS needs matching implementations (or a later, evidence-based shared substrate seam). Each Tumbleweed-specific script checks the OS before mutation so an incorrect binding fails on the target. Expansion checks interface bindings and types but cannot yet prove cross-module OS compatibility statically.

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

The flags confirm *your* verification of disposability and console access; the script cannot prove either. Its first action checks OS identity before installing Zsh or creating the account. Rerunning should preserve an existing matching account; an existing different shell requires an explicit migration. No VM execution or distribution-specific package verification has occurred.

## Limits

The interfaces' written guarantees still need real target-side testing, especially `/usr/bin/zsh` registration in `/etc/shells` on Tumbleweed. The planner validates declarations and bindings, not whether scripts fulfill their guarantees. Generated scripts and SSH credentials must not be committed. Provider changes, drift, interruption, password management and account migrations are out of scope. No NixOS behaviour has changed.
