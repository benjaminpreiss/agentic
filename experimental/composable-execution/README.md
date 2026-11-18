# Composable execution: pure planning prototype

**Question:** Can instances select invocation context through bound runtime and executor instances, instead of baking POSIX `sh`, UID 0, SSH, or an account name into the deployment model? This is an **independent, non-executing experiment** based on `main`, separate from [PR #41's original Tumbleweed script-rendering experiment](https://github.com/benjaminpreiss/agentic/pull/41). Nothing here logs into a host or runs a method. Do not use this plan to deploy a machine.

From this directory:

```sh
python3 -m unittest discover -s . -p 'test_*.py'
python3 plan.py --expand
```

`interfaces/*.json` describe OS, executor, Bash and Python runtimes, package manager, networking and workspace capabilities. A runtime's `run` method delegates to its bound executor's `invoke` method. `modules/*/module.json` implement these interfaces. The Tumbleweed network module uses **both** Bash and Python runtimes; their Bash/Python artifact formats are implementation-specific, not properties of the networking interface or planner. The workspace uses another instance of the *same* Bash runtime module. Each runtime's `methods.run.accepts` declares supported artifact formats; its `values.path` declares an implementation-specific interpreter path. The plan carries this under `runtime_values`, not as a universal `executable` field. These are static declarations, **not** observations that an interpreter exists on the target.

`instances/*.json` choose the bindings. The implementation modules are specific to **openSUSE Tumbleweed** (`opensuse-tumbleweed`, `tumbleweed-bash`, `tumbleweed-python3`, `tumbleweed-zypper`, `tumbleweed-networkd`, `tumbleweed-workspace`). Their interfaces remain conceptual. Only `external-executor` is not a Tumbleweed installation: it is an externally supplied bootstrap fixture.

```text
host → bash-admin → admin-executor (os-read)
packages → host + bash-admin → admin-executor (package-install)
python-admin → host + packages + admin-executor
network → host + bash-admin + python-admin → admin-executor (network-read)
workspace → host + bash-agent → agent-executor (workspace-read)
```

The `check-os` transition plans the Tumbleweed identity inspection before package, Python, network and workspace operations. This is **not** proof of OS identity at planning time. Bash cannot itself depend on `host` here: `host.inspect_identity` needs the Bash runtime, so that would create a cycle. A real bootstrap executor must first establish the target and verify an available way to perform the inspection; this prototype does not do so.

The executor instances are marked `provided`: they are **bootstrap capabilities supplied from outside this plan**, with no transition to install them. Their `target` and `grants` entries are fixture **claims**, not authentication or authorization. A real executor adapter must authenticate a target, enforce permissions for a reviewed artifact and return an observation. The planner checks matching target labels, grants claimed by the selected executor, reviewed method paths, runtime artifact format, and dependency order. It cannot prove that a Bash/Python binary is installed, a privilege exists, an artifact is immutable, or a method succeeded. Do not put credentials, secret tokens, or arbitrary code in instance inputs. No generic root account is assumed; names `admin` and `agent` identify two fixture executor instances, not OS-specific principals.

`requests.json` explicitly selects transitions. `install-python` invokes the universal package-manager `install(package)` method with `package: "python3"` through `bash-admin`; the network method selection then chooses `bash-admin` for its Bash artifact and `python-admin` for its Python artifact. A module cannot borrow the caller's more powerful executor implicitly. The method implementation artifact is **not executed by the planner**. Despite the network module's example name, it has **no `configure` method**: the Python artifact only validates an address. Staging or activating networkd, and transporting scripts to a target, are **not implemented**. Empty `bind-bash`/`bind-zypper` transitions are *selection-only* and do not establish that a runtime or package manager exists. As elsewhere in this repo, a requested `from: null` is an intention, never evidence of absence.

The older experiment in PR #41 has a separate `plan.py --script` and a Tumbleweed-only, UID-0 shell renderer. That renderer is **not** the execution engine of this model. This prototype establishes the binding/authorization *shape*, not a fully working runner or migration of the other Agentic capabilities.
