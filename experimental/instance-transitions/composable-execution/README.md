# Composable execution: pure planning prototype

**Question:** Can instances select invocation context through bound runtime and executor instances, instead of baking POSIX `sh`, UID 0, SSH, or an account name into the deployment model? This is a **new, non-executing design slice** alongside the older Tumbleweed script-rendering example. Nothing here logs into a host or runs a method. Do not use this plan to deploy a machine.

From this directory:

```sh
python3 -m unittest discover -s . -p 'test_*.py'
python3 plan.py --expand
```

`interfaces/*.json` describe executor, Bash and Python runtimes, package manager, networking and workspace capabilities. A runtime's `run` method delegates to its bound executor's `invoke` method. `modules/*/module.json` implement these interfaces. The Tumbleweed network module uses **both** Bash and Python runtimes; their Bash/Python artifact formats are implementation-specific, not properties of the networking interface or planner. The workspace uses another instance of the *same* Bash runtime module.

`instances/*.json` choose the bindings:

```text
network → bash-admin → admin-executor (network-read)
        → python-admin → admin-executor (network-read)
workspace → bash-agent → agent-executor (workspace-read)
python-admin → packages → bash-admin → admin-executor (package-install)
```

The executor instances are marked `provided`: they are **bootstrap capabilities supplied from outside this plan**, with no transition to install them. Their `target` and `grants` entries are fixture **claims**, not authentication or authorization. A real executor adapter must authenticate a target, enforce permissions for a reviewed artifact and return an observation. The planner checks matching target labels, grants claimed by the selected executor, reviewed method paths, runtime artifact format, and dependency order. It cannot prove that a Bash/Python binary is installed, a privilege exists, an artifact is immutable, or a method succeeded. Do not put credentials, secret tokens, or arbitrary code in instance inputs. No generic root account is assumed; names `admin` and `agent` identify two fixture executor instances, not OS-specific principals.

`requests.json` explicitly selects transitions. `install-python` invokes the universal package-manager `install(package)` method with `package: "python3"` through `bash-admin`; the network method selection then chooses `bash-admin` for its Bash artifact and `python-admin` for its Python artifact. A module cannot borrow the caller's more powerful executor implicitly. The method implementation artifact is **not executed by the planner**. The example Python artifact only validates an address; staging or activating networkd, and transporting scripts to a target, are **not implemented**. Empty `bind-bash`/`bind-zypper` transitions are *selection-only* and do not establish that a runtime or package manager exists. As elsewhere in this repo, a requested `from: null` is an intention, never evidence of absence.

The older sibling `plan.py --script` is still a **legacy Tumbleweed experiment** with a global UID-0 shell renderer. It must not be mistaken for the execution engine of this model. This prototype establishes the binding/authorization *shape*, not a fully working runner or migration of the other Agentic capabilities.
