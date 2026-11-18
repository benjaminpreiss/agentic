# Composable execution: pure planning prototype

**Question:** Can instances select invocation context through bound runtime and executor instances, instead of baking POSIX `sh`, UID 0, SSH, or an account name into the deployment model? This is an **independent execution-composition experiment** based on `main`, separate from [PR #41's original Tumbleweed script-rendering experiment](https://github.com/benjaminpreiss/agentic/pull/41). The planner is pure. `dispatch.py` can call bound methods only through explicitly injected executor adapters; this repo supplies **recording test adapters, not local or SSH runners**. Do not use this prototype to deploy a machine.

From this directory:

```sh
python3 -m unittest discover -s . -p 'test_*.py'
python3 plan.py --expand
```

`interfaces/*.json` describe OS, executor, Bash and Python runtimes, package manager, networking and workspace capabilities. A runtime's `methods.run.calls` declares an invocation of its bound executor's `invoke` method, and `dispatch.py` interprets that call with an injected executor adapter. There is no `implementation: delegate` placeholder. `modules/*/module.json` implement these interfaces. The Tumbleweed network module uses **both** Bash and Python runtimes; their Bash/Python artifact formats are implementation-specific, not properties of the networking interface or planner. The workspace uses another instance of the *same* Bash runtime module. Each runtime's `methods.run.accepts` declares supported artifact formats; its `values.path` declares an implementation-specific interpreter path. The plan carries this under `runtime_values`, not as a universal `executable` field. These are static declarations, **not** observations that an interpreter exists on the target.

`instances/*.json` choose the bindings. The implementation modules are specific to **openSUSE Tumbleweed** (`opensuse-tumbleweed`, `tumbleweed-bash`, `tumbleweed-python3`, `tumbleweed-zypper`, `tumbleweed-networkd`, `tumbleweed-workspace`). Their interfaces remain conceptual. **There is no executor module in this experiment.** The two `provided` executor instances refer directly to `interface/executor@1`, naming injection points rather than claiming an implementation.

```text
host → bash-admin → admin-executor (os-read)
packages → host + bash-admin → admin-executor (package-install)
python-admin → host + packages + admin-executor
network → host + bash-admin + python-admin → admin-executor (network-read, network-stage)
workspace → host + bash-agent → agent-executor (workspace-read)
```

The `check-os` transition plans the Tumbleweed identity inspection before package, Python, network and workspace operations. This is **not** proof of OS identity at planning time. Bash cannot itself depend on `host` here: `host.inspect_identity` needs the Bash runtime, so that would create a cycle. A real bootstrap executor must first establish the target and verify an available way to perform the inspection; this prototype does not do so.

The executor instances are marked `provided`: they are **interface-only bootstrap references supplied from outside this plan**, with no module or transition to install them. There is no `implementation: external` method declaration. `dispatch.run_requested(executors)` interprets requested calls in dependency order; it requires an explicit adapter for **every** bound executor before starting, calls `runtime.run → executor.invoke`, stops on a nonzero exit result and returns invocation-scoped observations without persisting them. No production adapter or command-line execution entry point is included. Supplying a real adapter would cross the execution boundary and could change a target. Their `target` and `grants` entries are fixture **claims**, not authentication or authorization. A real executor adapter must authenticate a target, enforce permissions for a reviewed artifact and return an observation. The planner checks matching target labels, grants claimed by the selected executor, reviewed method paths, runtime artifact format, and dependency order. It cannot prove that a Bash/Python binary is installed, a privilege exists, an artifact is immutable, or a method succeeded. Do not put credentials, secret tokens, or arbitrary code in instance inputs. No generic root account is assumed; names `admin` and `agent` identify two fixture executor instances, not OS-specific principals.

`requests.json` explicitly selects transitions. `install-python` invokes the universal package-manager `install(package)` method with `package: "python3"` through `bash-admin`. The requested `stage-networkd` transition plans a network inspection through `bash-admin` followed by `network.configure` through the bound `python-admin` runtime. `check-network` is an alternative **inspection-only** request. A module cannot borrow the caller's more powerful executor implicitly. **The planner does not invoke either method**, and the packaged recording adapters only observe the call envelopes, so this fixture stages nothing.

If independently delivered to and invoked on a disposable Tumbleweed target by a future trusted executor, `modules/tumbleweed-networkd/methods/stage.py` would validate interface name, MAC and DHCP/static IPv4 inputs; check the *live* interface MAC, OS identity, active systemd-networkd and absent competing managers; then atomically stage only `/etc/systemd/network/10-agentic.network`. It refuses linked directories/files and an existing unmanaged file. The checked-in `vm-uplink`/zero MAC inputs are deliberately unusable. It **never restarts/reloads networkd or tests external SSH reachability**. An external restart could still activate a staged file; no guarded activation, timed rollback or independent connection check is implemented. The `network-stage` grant in JSON is only a claim, not an enforced permission. Empty `bind-bash`/`bind-zypper` transitions are *selection-only* and do not establish that a runtime or package manager exists. As elsewhere in this repo, `from: null` is an intention, never evidence of absence.

The older experiment in PR #41 has a separate `plan.py --script` and a Tumbleweed-only, UID-0 shell renderer. That renderer is **not** the execution engine of this model. This prototype establishes the binding/authorization *shape*, not a fully working runner or migration of the other Agentic capabilities.
