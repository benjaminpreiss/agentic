# Mapping the current Agentic NixOS repo to the draft model

This is a **historical inventory of behaviors to replace**, not the proposed interface structure (see [INTERFACE-STRUCTURE.md](INTERFACE-STRUCTURE.md)) and not an executable NixOS plan. It maps the supported deployment at `origin/main` (`f73e8ca`) to proposed interfaces, modules, instances, transitions, and instance methods. The runnable examples in this directory cover the original three-interface introduction plus a separate Tumbleweed networkd/Python-dependency example, not the full catalog. Nothing here changes `nixos/`, stages a new flake, or validates a VM deployment.

## Separate the five roles

| Role | NixOS repo today | In the proposed model |
| --- | --- | --- |
| Interface | No equivalent artifact. NixOS options and systemd units describe parts of a configuration but do not form our deployment interfaces. | Contract for a capability's declared values and **instance methods**, including effects, errors and when an observation is valid. |
| Module | `nixos/modules/*.nix` are **NixOS configuration fragments**, not necessarily one-for-one implementations of our interfaces. | Reusable implementation of an interface. It declares values/configuration/dependencies and implements its methods. A NixOS-backed module might produce a configuration fragment or wrap a runtime operation. |
| Instance | `.deployment/generated/machine.nix`, the flake input lock, configuration `agentic`, and per-machine selections concretize one machine's system. | Deployment-scoped selection/configuration/bindings, e.g. an Agentic OS installation, an `agentic` account, backup, and GitHub integration. No new host interface is assumed here; the SSH target remains an external execution context. |
| Transition | `scripts/install/deploy.sh --install`, `scripts/update/apply.sh` and the NixOS activation they invoke are executable workflows. | Separately requested operations introducing or replacing the selected implementation for an instance. Their scripts inspect live preconditions, not a saved prior-state file. |
| Method | Installed commands and on-demand sockets already have callable behavior, though no draft method declaration or dispatch exists. | An operation on a **bound instance**, defined by its interface and implemented by its module. Its observations apply when invoked, not forever. |

## Candidate capability slices (not a file-to-file conversion)

| Candidate interface / instance | Existing source | Module implementation and bindings to explore |
| --- | --- | --- |
| OS installation / `agentic-system` | `nixos/flake.nix`, `nixos/modules/base.nix`, `nixos/modules/disk.nix`, `.deployment/generated/machine.nix`, `.deployment/generated/facter.json` | A machine-specific NixOS configuration assembled from reusable pieces, locked inputs and selected disk/network/SSH settings. `disk.nix` is **install-only**: it must not become a step in an ordinary update. This bundle is not equivalent to the Tumbleweed OS module. |
| Account and login shell / `agentic` | `nixos/modules/base.nix`, `nixos/modules/agentic.nix` | `users.users.agentic` with SSH key, Zsh, home/workspace and shell initialization. The shell is selected through Nix (`pkgs.zsh`), not a guessed target path or a runtime template output. |
| Recovery access / `recovery` | `nixos/modules/recovery.nix`, `scripts/install/recovery-password.sh` | Console-only fallback with a password hash delivered outside the Nix store. The hash is sensitive deployment input, **not** a publishable module value. |
| Sandboxed agent launch / `pi`, `omp` | `nixos/modules/agentic.nix`, `nixos/profiles/*.json` | Launchers and local nono profiles; Pi binds to Herdr and the GitHub MCP/Git credential sockets. Socket permissions and sandbox rules are part of the capability contract, not merely a binary path. |
| Skills / `agentic-skills` | `skills/available/`, `skills/enabled/`, `nixos/modules/agentic.nix`, `scripts/stage.sh` | Versioned, checked-in skill content and activation-installed links. Content artifacts need not each become an instance or a method. |
| GitHub integration / `github` | `nixos/modules/github-mcp.nix`, `scripts/runtime/git-app-token-broker.sh`, `scripts/runtime/git-credential-helper.sh`, `scripts/github/*.sh` | Local MCP and Git credential sockets, GitHub App token brokerage and configuration. App key/IDs are target-side credentials, never static published values or part of a Nix store artifact. |
| Backup / `agentic-backup` | `nixos/modules/agentic.nix` | Installed backup command plus systemd timer, local archive retention of 14. A generated archive name is a **runtime result**, not a value used in pure expansion. On-server archives are not off-server backups. |
| Diagnostics / `firstboot`, protection audit | `nixos/modules/firstboot.nix`, `nixos/modules/github-mcp.nix` | First-boot console observations and a scheduled GitHub protection audit. The audit's status/report are application data, **not** evidence of which deployment transition ran. |

These slices are candidates, not a mandate to split each NixOS option or file into its own artifact. NixOS merges the fragments into **one evaluated system**; the current JSON experiment cannot yet express that multi-module assembly. A real mapping must decide whether the composed NixOS system is one module implementation, or whether modules can contribute to a shared composition without falsely claiming independent installation.

## Operations versus methods

| Today | Proposed classification | Why |
| --- | --- | --- |
| `scripts/install/prepare.sh`, `scripts/install/preflight.sh` | Operator preparation and live preflight for an **install transition**, not constructors or evidence of lasting target state. | SSH discovery, disk/boot/network confirmation, generated machine inputs, assertion evaluation and manual recovery checks precede destructive action. |
| `scripts/install/deploy.sh --install` | Explicit **introduce** operation for the composed NixOS installation. | It repeats preflight, requires `ERASE-AND-INSTALL-NIXOS`, and invokes nixos-anywhere/Disko. Never substitute it for an update. |
| `scripts/update/apply.sh` | Explicit **replace/reapply** operation for an existing NixOS installation. | It stages the flake, evaluates, confirms and switches via `nixos-rebuild`; it must not repartition. Secret syncing and post-activation nono verification are separate steps; the latter can fail after activation. |
| `agentic-backup` command | Candidate `Backup.run` **instance method**. | Invocable after installation, optionally on a timer. Its archive path is observed at call time. |
| Git credential socket / token broker | Candidate `GitCredentials.getForRepository` **instance method**. | Mint a scoped token per request; never expose the App private key through the interface. |
| GitHub MCP socket | Candidate GitHub-integration **instance methods**, rather than a deployment transition per tool call. | Each request uses an installed capability at execution time. The external API and permissions may change. |
| Protection audit and report command | Candidate `ProtectionAudit.run` / `readReport` **instance methods**. | A report describes one observation; a timer triggers further invocations. It is not a deployment log. |

The methods above are **design proposals**; backup and GitHub operations have no Tumbleweed implementation yet. The planner supports method dispatch in the small existing examples. A transition script remains responsible for ordering calls, checking live conditions and reporting partial failure. Runtime method results must not be smuggled into the experiment's pre-target static-value expansion. Configuring an installed timer is deployment work; each later timer firing is not a new transition request.

## First concrete slice to validate next

Model a **backup capability** without deploying it: specify `Backup.run`'s input/output/error contract, bind one `agentic-backup` instance to the OS/account it operates on, and show an external transition that installs or replaces that implementation. The module would implement `run`; the transition would still own installation. This tests the proposed method seam using the actual backup command before attempting a full NixOS translation. Keep credentials out of generated JSON and do not execute backups on the development machine.
