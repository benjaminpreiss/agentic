# Sandboxed Pi and Oh My Pi

The NixOS setup installs **`pi` and `omp` as sandbox launchers**.

## Use

From the `agentic` account:

```sh
cd ~/work
pi   # Pi inside nono
omp  # Oh My Pi inside nono
```

Both launchers require the current directory to be under `~/work` and forward arguments to the agent. The Pi profile grants read/write access to the launch directory via `--allow-cwd`, **not** the whole `~/work` tree: launch from the project directory rather than `~/work` if sibling projects must remain inaccessible. The inherited Pi pack still grants access to Pi's own configuration and required system paths. They use separate nono profiles in [`nixos/profiles/`](../nixos/profiles/):

| Command | Profile | Base pack | Socket grant |
| --- | --- | --- | --- |
| `pi` | `pi-herdr` | `nolabs-ai/pi` | GitHub MCP |
| `omp` | `omp-agentic` | `nolabs-ai/omp` | Git credential socket (for pushes) |

The GitHub App private key stays **outside** both sandboxes. Pi and OMP have separate agent configurations; OMP provider login and settings are not provisioned automatically.

Pi's `suppress_save_prompt: ["/"]` prevents denied paths from being offered for an interactive profile-save grant on exit. It does **not** grant access or hide denial diagnostics. A denial (including `/tmp`) must be investigated and any needed access changed deliberately outside the session; do not grant all of `/tmp` to avoid a warning. This setting applies to both interactive `pi` and `pi -p ...`. OMP has a separate profile and still grants all of `~/work`.

## Select installed skills

Reviewed, versioned skills live in [`skills/available/`](../skills/available/); [`skills/enabled.nix`](../skills/enabled.nix) selects which ones NixOS installs. Remove a manifest entry to disable a skill without deleting its source. Run `bash scripts/test-deployment.sh` to check selections before deploying; existing hosts may also run `bash scripts/test-stage.sh` before a legacy [update](update.md). Missing or escaping paths fail validation; user-managed skills outside `~/.pi/agent/skills/agentic` are not overwritten. Imported Matt Pocock skills are enabled by default; see [their provenance](../skills/available/mattpocock/IMPORT.md) and [the selection decision](adr/0001-select-skills-with-checked-in-symlinks.md).

## What the wrappers do—and do not protect

The raw agent packages are referenced by Nix store paths inside the wrappers, not installed on the system `PATH`. Interactive Zsh prioritizes the wrappers over `~/.local/bin`, so ordinary command lookup uses nono.

This is **not a host-wide execution restriction**. Someone explicitly calling a raw Nix store binary by absolute path can bypass the wrapper; other custom `PATH` overrides may also take precedence outside the configured interactive shell. Enforcing sandboxing against deliberate bypass requires a separate host-level policy.
