# Independent draft: module instances and separate deployment transitions

**Question:** Can modules declare interface capabilities and static information while independent transitions bring instances into use? This runnable subset has static values and three implemented inspection methods; most catalog methods are **not implemented**. [INTERFACE-STRUCTURE.md](INTERFACE-STRUCTURE.md) describes the complete proposed Tumbleweed interface catalog, its dependencies and method contracts; only three interfaces have example modules and transitions so far. [CURRENT-REPO-MAP.md](CURRENT-REPO-MAP.md) records which supported NixOS behaviors need replacement, not a Nix implementation of the new system. The experiment starts from `main`; it does **not** change [draft PR #39](https://github.com/benjaminpreiss/agentic/pull/39) or the supported NixOS deployment. JSON is the canonical representation; a typed authoring language could emit it later. Artifact declarations use `(kind, authority, name, version)` coordinates; references have a compact string syntax.

```text
interfaces/*.v1.json                   whole proposed capability catalog; three runnable examples
modules/*/{module.json,methods/*.sh}    implementations, declared values and instance methods; no transitions
instances/*.json                       desired configured instances and provider bindings
requests/introduction.json             explicit transitions to run for those instances
transitions/introduce-os/{transition.json,run.sh}
transitions/introduce-zsh/{transition.json,run.sh}
transitions/introduce-account/{transition.json,run.sh}
plan.py                                validates requests, resolves arguments, orders dependencies
```

Every interface, module and transition declares its artifact identity **at the document root**, rather than under an `id` wrapper. Within an artifact declaration, references may omit the enclosing authority:

```json
{
  "kind": "module",
  "authority": "did:web:agentic.invalid",
  "name": "linux-local-account",
  "version": 1,
  "implements": "interface/account@1",
  "requires": ["interface/os@1", "interface/login-shell@1"]
}
```

A cross-authority reference—or any reference from an instance or transition request, which has no enclosing authority—uses `did:<method>:<id>#<kind>/<name>@<version>`, for example `did:web:agentic.invalid#module/linux-local-account@1`. The fragment is **this experiment's artifact-coordinate convention** inside DID URL syntax. It is not a new DID method, an implemented DID URL dereferencing profile, or a claim that resolving the DID yields the artifact. The planner parses and type-checks the string against locally loaded JSON documents; it never contacts a DID resolver. The expanded plan shows normalized structured coordinates for inspection.

`kind` distinguishes artifact categories; `authority` is an opaque **claimed DID** controlling the name; `name` is local to that authority and kind; `version` is a positive artifact revision, independent of PostgreSQL or other installed software versions. The planner rejects duplicate coordinates within its loaded artifact set and validates the kind of each reference. Artifact file paths do not define identity, so different versions can coexist. `did:web:agentic.invalid` is an intentionally **unresolvable fixture**, not a verified authority or a decision to use `did:web` for publication. No DID resolution, signature, authorization, canonical-byte packaging or historical immutability enforcement exists here. A future publication process must prevent republishing changed bytes under the same coordinate; an identifier alone cannot establish trust or globally prevent an imposter from claiming authority. Instance IDs such as `agentic` remain stable and deployment-scoped, not versioned artifact IDs.

A module packages its instance method handlers under `modules/*/methods/`; an interface defines each method's parameters and invocation-scoped guarantee. The current three handlers (`os.inspect_identity`, `login-shell.inspect`, `account.inspect`) are read-only. A transition may declare ordered `calls` on its own instance or a directly bound provider before or after its `run.sh`. The planner checks the provider, method name, parameters and handler path, then renders the handler with explicit arguments into the generated script. The account example's tests also exercise a bound login-shell method. A method's observation is not persistent target state; **do not pass secret values via rendered arguments**. No dynamic method result is available to pure expansion.

A **transition** has an exact `from` module and `to` module for one interface. `null → module` introduces an instance, `module A → module B` changes its implementation, and `module → null` removes it. At least one endpoint must be non-null. Each transition has **its own directory and script**; transition scripts do not live in modules. Module-owned method scripts are separate from transitions. The request explicitly names each transition and instance; the planner neither chooses one from a previous-state file nor keeps an execution log. `from: null` is a declaration of the intended operation, **not proof of absence on the target**. An old→new migration script must check its real target-side preconditions before changing anything. Only three introduction transitions ship here. Upgrade/removal scripts in tests are synthetic selection examples, not deployable migrations.

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
