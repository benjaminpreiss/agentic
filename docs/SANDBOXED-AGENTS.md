# Sandboxed Pi and Oh My Pi

The NixOS setup installs **`pi` and `omp` as sandbox launchers**.

## Use

From the `agentic` account:

```sh
cd ~/work
pi   # Pi inside nono
omp  # Oh My Pi inside nono
```

Both launchers require the current directory to be under `~/work` and forward arguments to the agent. They use separate nono profiles in [`profiles/`](../profiles/):

| Command | Profile | Base pack | Socket grant |
| --- | --- | --- | --- |
| `pi` | `pi-herdr` | `nolabs-ai/pi` | GitHub MCP |
| `omp` | `omp-agentic` | `nolabs-ai/omp` | Git credential socket (for pushes) |

The GitHub App private key stays **outside** both sandboxes. Pi and OMP have separate agent configurations; OMP provider login and settings are not provisioned automatically.

## Deploy

On an existing machine, refresh `.deployment/flake.lock` on your deployment computer to include the new OMP flake input, then review the lock change before running `scripts/apply.sh`:

```sh
cd .deployment
nix flake lock --update-input omp
cd ..
bash scripts/apply.sh
```

`prepare.sh` stages the profiles for fresh installs; `apply.sh` stages them for updates. Apply pulls both nono packs as `agentic` and dry-runs both profiles. If either pull or check fails, verification stops. This PR has **not** been evaluated on a generated machine configuration or exercised against a live OMP pack.

## What the wrappers do—and do not protect

The raw agent packages are referenced by Nix store paths inside the wrappers, not installed on the system `PATH`. Interactive Zsh prioritizes the wrappers over `~/.local/bin`, so ordinary command lookup uses nono.

This is **not a host-wide execution restriction**. Someone explicitly calling a raw Nix store binary by absolute path can bypass the wrapper; other custom `PATH` overrides may also take precedence outside the configured interactive shell. Enforcing sandboxing against deliberate bypass requires a separate host-level policy.
