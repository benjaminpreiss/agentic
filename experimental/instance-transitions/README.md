# Independent draft: module instances and separate deployment transitions

**Question:** Can modules declare only interface capabilities and static information while independent transitions move an instance between module implementations? This experiment starts from `main`; it does **not** modify [draft PR #39](https://github.com/benjaminpreiss/agentic/pull/39) or the supported NixOS deployment. Its JSON is the canonical representation; a typed authoring language could emit the same documents later.

```text
interfaces/{os,login-shell,account}.v1.json  concepts and static value types, no ensure
modules/*/module.json                   implementations, values and required interfaces, no scripts
instances/*.json                       desired configured instances and provider bindings
state/absent.json                      explicit *claimed* previously applied modules
transitions/introduce-os/{transition.json,run.sh}
transitions/introduce-zsh/{transition.json,run.sh}
transitions/introduce-account/{transition.json,run.sh}
plan.py                                selects and orders transitions, renders a shell script
```

A **transition** has an exact `start` module and `end` module for one interface. `null → module` introduces an instance, `module → null` removes one, and `module A → module B` changes its implementation (e.g. PostgreSQL 12 → 14). At least one endpoint is required. Each transition has **its own directory and script**; scripts do not belong to modules. This draft ships only three introduction transitions. Tests create *test-only* upgrade/removal transitions to exercise the selector; they are not production upgrade or removal scripts. Transitions can read static values, instance configuration and values from bound provider instances on their start or end side. `introduce-account` receives both `account_name` and the path supplied by its bound Zsh instance, `/usr/bin/zsh`, before execution.

Planning requires an **explicit previous-state record**; it never infers absence or discovers target state. An entry must exist for every desired instance, including one with `module: null`. A known pair without an explicit matching transition fails closed: even rerunning with unchanged modules requires a deliberate `A → A` reconcile transition (not provided). A real applied-state ledger, immutable module identities, target checks, transactions and recovery remain open design questions. Do not treat `state/absent.json` as a discovery result or use it on an existing machine.

## Inspect without contacting a target

From this directory:

```bash
cd experimental/instance-transitions
python3 -m unittest discover -s . -p 'test_*.py'
python3 plan.py --from state/absent.json --expand
python3 plan.py --from state/absent.json --script > introduction.generated.sh
sh -n introduction.generated.sh
```

The expanded JSON shows each transition's endpoints, bindings, script path, resolved argument values and their source. The OS, Zsh, and account scripts are moved under their respective introduction transition folders. The Zsh transition installs and verifies **the declared path**; it does not discover a path for substitution. The account transition uses a Linux-local account script (no hard-coded `agentic` or Zsh path). No Ansible is used.

## Execution: not validated

The generated script installs Zsh and may create a local account. **Only on a newly installed disposable Tumbleweed VM**, after a snapshot and verification of out-of-band console access, inspect the script and run it manually:

```bash
ssh -T -i /private/path/to/key vm-user@disposable-vm \
  'sudo env AGENTIC_DISPOSABLE_VM=true AGENTIC_CONSOLE_VERIFIED=true sh -s' \
  < introduction.generated.sh
```

**Do not run it on the development host.** The flags are human attestations, not proof of disposability; the first script checks Tumbleweed identity before mutation. There has been **no VM run, multi-distribution validation, shellcheck, migration execution or Ansible syntax check**. A script may fail partway through; the planner does not record progress or automatically update applied state. A script's successful exit must not be interpreted as proof of an atomic transition. Do not commit secrets or generated scripts.
