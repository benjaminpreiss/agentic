# Whole-system interface structure — existing openSUSE Tumbleweed

The 24 JSON declarations in `interfaces/` are the **proposed interface catalog** for replacing the current Agentic NixOS functionality on an already installed openSUSE Tumbleweed machine. Each interface declares the other interfaces it requires, the values it offers (if any), and method names with input names and observable guarantees. These declarations do not install or run anything. Only the older `os`, `login-shell`, and `account` examples have module implementations and transitions today; **the newly named methods have no implementations or invocation support in `plan.py` yet**. Do not treat catalog completeness as a completed migration.

An arrow `A → B` below means the instance providing **A requires a direct binding to B**. The planner checks that an implementing module declares at least those bindings and rejects unknown or cyclic interface dependencies. Implementations may have additional bindings. Interfaces describe capabilities, not a guarantee of lasting machine state.

| Interface | Requires | Functionality covered from the existing repo |
| --- | --- | --- |
| `os` | — | Verify the Tumbleweed substrate. Existing OS installation is a prerequisite; no Disko or bootloader installer is carried forward. |
| `package-manager` | `os` | Reviewed installation and inspection of packages, replacing the package parts of the NixOS bundle with zypper-backed methods. |
| `networking` | `os` | Network configuration and live address/route inspection. Network changes need an external connectivity check and recovery path. |
| `firewall` | `networking` | Caller-owned ingress rules and policy observation. The firewall owns the rules, not each consumer. |
| `ssh-access` | `networking`, `firewall` | SSH port, key-only policy, root login and listening checks. Its transition can call the bound firewall instance to allow its port; externally verify access before closing an old port. |
| `intrusion-prevention` | `ssh-access` | SSH login-abuse protection (existing Fail2ban behavior). |
| `mandatory-access-control` | `os` | AppArmor policy activation and observation. |
| `kernel-hardening` | `os` | sysctl restrictions for kernel information, links and redirect acceptance. |
| `login-shell` | `os` | Declared login-shell path, Zsh installation/verification and shell setup. |
| `account` | `os`, `login-shell` | Unprivileged agent account, configured shell and SSH key. The existing prototype calls this `account`; it is the `local-account` candidate, not a second interface. |
| `recovery-access` | `os` | Independent console recovery account and its credential delivery; it must not depend on the agent account or its shell. Human console verification remains required. |
| `workspace` | `account` | Workspace directory and ownership. |
| `git-client` | `package-manager` | Git executable, author identity and credential-helper configuration. GitHub API clients do **not** depend on Git. |
| `sandbox` | `os` | nono profiles and sandboxed process launch; Herdr-backed Pi usage is an implementation dependency. |
| `agent-harness` | `account`, `workspace`, `sandbox` | Separate Pi and OMP instances with sandboxed launchers; runtime tools such as Node must be packaged by their implementations. |
| `skills` | `agent-harness` | Reviewed, pinned skill selection and symlink activation without clobbering user entries. |
| `backup` | `account` | Local archive production, verification and retention; returned archive path is a runtime result, not a declared value. Scheduling is an optional module binding. |
| `scheduler` | `os` | Shared timer capability for backup and protection audit, when requested by an implementation. |
| `diagnostics` | `os` | First-boot observations, including network/SSH observations without declaring them always healthy. |
| `status-screen` | `account` | Snapshot of tools, backups and audit results for an interactive login. |
| `github-app-credentials` | `os` | Safe target-side credential availability. Never put a private key or token in an interface value, instance JSON, generated script or Nix store. |
| `github-mcp` | `github-app-credentials`, `agent-harness` | Local MCP transport and client configuration. It uses the GitHub API, not the Git executable. |
| `git-credentials` | `git-client`, `github-app-credentials` | Installation token brokerage and Git credential-helper integration, scoped to a repository. |
| `github-protection-audit` | `github-app-credentials` | Read-only API audit and timestamped report. A scheduled implementation additionally binds `scheduler`. |

**Security profile, not an interface:** firewall, intrusion prevention, mandatory access control, and kernel hardening stay separate. **Tool collection, not an interface:** curl, jq, Node, Ghostty terminfo, Starship, etc. are packaged by the Tumbleweed modules that need them or a reviewed package set; a pass-through `command-line-tools` interface would add no useful method seam. **Provider inputs, not publishable values:** target SSH destination, public keys, recovery hash, GitHub App credentials, selected network settings. None are proof of live state. Preparation, preflight, rollout, update and secret delivery remain separate workflows/transitions, not automatically inferred from this graph.

The old NixOS files are a checklist of required behavior only. The interface catalog itself contains **no Nix implementation**, and it is not a runnable Tumbleweed deployment. The next step is to package and test module method implementations and explicitly requested transitions for each capability, preserving the existing console/SSH safety gates rather than silently installing everything.
