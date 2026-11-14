# Independent draft: Python classes for deployment modules

**Question:** Can Python protocols, classes, and object bindings express conceptual interfaces, concrete modules, and configured instances more clearly than the JSON DSL in [draft PR #39](https://github.com/benjaminpreiss/agentic/pull/39)? This is a **separate experiment based on `main`**. PR #39 remains open and unchanged. Neither experiment replaces the supported NixOS deployment.

## The three concepts

- `interfaces_v1.py`: conceptual `OperatingSystem`, `LoginShell` and `Account` protocols. `LoginShell.path()` is a pure, no-argument static declaration; `ensure(target)` is a transition. `Target` and `Module` are internal planner/execution typing seams, not extra host-domain interfaces.
- `modules.py`: concrete `OpenSuseTumbleweed`, `ZshOnTumbleweed` and `LinuxLocalAccount` classes. Zsh owns `/usr/bin/zsh` and its Tumbleweed-specific script. The reusable Linux account class owns neither `agentic` nor a Zsh path. Its script uses `useradd`, `getent`, `/etc/passwd` and `/etc/shells` rather than imposing a Tumbleweed identity. The OS and Zsh scripts check Tumbleweed identity before mutation.
- `instances.py`: `host`, `interactive` and `agentic` are configured objects. Python references bind the shell to the OS instance and the account to both the OS and shell instances. The account calls its bound shell's `path()` during expansion, without runtime shell discovery.

`expand()` calls `ensure()` with a **non-executing recorder**, collecting an inspectable ordered task plan. `render()` embeds the concrete modules' scripts into a standalone shell script. No Ansible or remote commands run during expansion. `ensure()` could still perform arbitrary effects if a module bypasses the recorder: Python typing does **not** prove purity. The module implementations and scripts are trusted code in this prototype.

## Inspect locally

From the repository root:

```bash
python3 -m unittest discover -s experimental/python-modules -p 'test_*.py'
python3 experimental/python-modules/plan.py --expand
cd experimental/python-modules
python3 plan.py --script > introduction.generated.sh
sh -n introduction.generated.sh
```

Python 3.9+ standard library only. The tests exercise static expansion, two configured accounts sharing a shell, a test-only alternative shell implementation, dependency errors and script syntax. No static type checker is installed here, so annotations have **not** been checked with mypy or pyright.

## Target execution: not yet validated

The generated script installs Zsh and may create a local account. **Only on a freshly installed disposable openSUSE Tumbleweed VM**, after a snapshot and verification of out-of-band console access, inspect the generated script and then run it manually:

```bash
ssh -T -i /private/path/to/key vm-user@disposable-vm \
  'sudo env AGENTIC_DISPOSABLE_VM=true AGENTIC_CONSOLE_VERIFIED=true sh -s' \
  < introduction.generated.sh
```

Do **not** run it on the development host. The flags are human attestations; they cannot prove the VM is disposable. The path `/usr/bin/zsh` and shell registration in `/etc/shells` are target-side expectations checked at execution, not discovered outputs. No VM run, shellcheck, multi-distribution account test, migration or interrupted-transition recovery has been performed. An existing account with a different shell is refused rather than silently migrated. Do not commit secrets, inventory, or generated scripts.

## What this experiment does not answer

Python protocols improve composition readability but do not inherently enforce interface versions at runtime, static purity, cross-substrate compatibility, applied-state tracking or PostgreSQL-style version migrations. A production framework would need explicit validation and recorded state before it can safely change live bindings or resource versions. This PR is for evaluating the class-based model, **not for merging a new installer**.
