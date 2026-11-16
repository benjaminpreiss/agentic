# Independent draft: module instances and separate deployment transitions

**Question:** Can modules declare only interface capabilities and static information while independent transitions bring instances into use? This experiment starts from `main`; it does **not** change [draft PR #39](https://github.com/benjaminpreiss/agentic/pull/39) or the supported NixOS deployment. JSON is the canonical representation; a typed authoring language could emit it later.

```text
interfaces/{os,login-shell,account}.v1.json  conceptual contracts and static value types
modules/*/module.json                   implementations, values and required interfaces; no scripts
instances/*.json                       desired configured instances and provider bindings
requests/introduction.json             explicit transitions to run for those instances
transitions/introduce-os/{transition.json,run.sh}
transitions/introduce-zsh/{transition.json,run.sh}
transitions/introduce-account/{transition.json,run.sh}
plan.py                                validates requests, resolves arguments, orders dependencies
```

A **transition** has an exact `from` module and `to` module for one interface. `null → module` introduces an instance, `module A → module B` changes its implementation, and `module → null` removes it. At least one endpoint must be non-null. Each transition has **its own directory and script**; scripts do not live in modules. The request explicitly names each transition and instance; the planner neither chooses one from a previous-state file nor keeps an execution log. `from: null` is a declaration of the intended operation, **not proof of absence on the target**. An old→new migration script must check its real target-side preconditions before changing anything. Only three introduction transitions ship here. Upgrade/removal scripts in tests are synthetic selection examples, not deployable migrations.

## Argument references

`transitions/introduce-account/transition.json` includes:

```json
"args": [
  {"side": "to", "name": "account_name"},
  {"side": "to", "name": "shell_path"}
]
```

These are the positional arguments passed to that transition's `run.sh`, **not** runtime outputs. `side: "to"` reads the destination instance's declaration: `account_name` is the configured name and `shell_path` is a static value from the bound login-shell instance. The planner resolves both before contacting a target. A transition with a `from` module can use `side: "from"` to read that module's declared values or explicitly provided `from_inputs`/`from_bindings` in its **request**, not a recorded observation. The expanded plan retains source provenance.

## Inspect without contacting a target

From this directory:

```bash
cd experimental/instance-transitions
python3 -m unittest discover -s . -p 'test_*.py'
python3 plan.py --requests requests/introduction.json --expand
python3 plan.py --requests requests/introduction.json --script > introduction.generated.sh
sh -n introduction.generated.sh
```

The generated script orders the OS, Zsh, and account introductions by instance bindings. Zsh installs and verifies its **declared** `/usr/bin/zsh` path; it does not discover a value for substitution. The reusable Linux account module contains neither `agentic` nor a shell path. No Ansible is used.

## Execution: not validated

The generated script installs Zsh and may create a local account. **Only on a newly installed disposable Tumbleweed VM**, after a snapshot and verification of out-of-band console access, inspect it and run it manually:

```bash
ssh -T -i /private/path/to/key vm-user@disposable-vm \
  'sudo env AGENTIC_DISPOSABLE_VM=true AGENTIC_CONSOLE_VERIFIED=true sh -s' \
  < introduction.generated.sh
```

**Do not run it on the development host.** The flags are human attestations, not proof of disposability; the first script checks Tumbleweed identity before mutation. There has been **no VM run, multi-distribution validation, shellcheck, migration execution or Ansible syntax check**. The planner does not record executions or know what might have changed outside it. A script may fail partway through; the generated script does not recover or roll back. Do not commit secrets or generated scripts.
