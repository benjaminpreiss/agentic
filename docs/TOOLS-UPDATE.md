# Agentic NixOS: Herdr remote-only setup

This update removes the separate Herdr Core (`hc`) bootstrap service and timer. It keeps the Herdr executable on the server for `herdr machine add` connections from your laptop. Pi, nono, the pinned skills, backup timer, and Nix tooling are unchanged.

## Files to change

- **Replace** `modules/agentic.nix`.
- **Replace** `scripts/apply.sh` (only updates its completion message).
- **Replace** `docs/TOOLS-UPDATE.md` with this guide (or merge into your documentation).
- `flake.nix` **unchanged**. Keep the Herdr flake input.
- No new files are required.

## Apply without reinstalling

Copy the files above into your project, preserving `.deployment/`.

From your Mac, in the repository root:

```bash
bash scripts/apply.sh
```

The helper copies `flake.nix` and `modules/agentic.nix` into `.deployment/`, evaluates the system and requests confirmation before `nixos-rebuild switch`. It **does not run disko or format disks**.

If the old Herdr Core unit was already activated on an earlier NixOS generation, the new generation no longer defines it. After applying, inspect for any old independently installed binary:

```bash
systemctl list-unit-files 'agentic-herdr-core*'
ls -l ~/.local/bin/hc 2>/dev/null || true
```

Only remove a leftover `hc` binary if you know it was installed by the previous helper and no other software uses it. Deleting it is not part of the declarative switch.

## Verify remote Herdr

On the NixOS server:

```bash
command -v pi nono herdr nnpi
herdr --version
systemctl status agentic-skills.service --no-pager
systemctl list-timers agentic-nono-pack.timer agentic-backup.timer
```

Install the optional Pi agent-state integration as `agentic` if needed:

```bash
herdr integration install pi
```

From the **laptop**, use your SSH alias:

```bash
herdr machine add <your-ssh-alias>
```

Herdr's remote server lifecycle is managed by your local Herdr client. This configuration does not start a second TUI or install `hc`.

## Launch sandboxed Pi

```bash
cd ~/work
nnpi
```

The launcher passes arguments to Pi, exports `HERDR_AGENT=pi` and `JITI_FS_CACHE=false`, and refuses to start outside the workspace instead of silently changing directories.

## Updates

Pi, nono, Herdr and Matt Pocock skills stay pinned in `.deployment/flake.lock`. Updating these requires reviewing and rebuilding the flake; nono registry pack refresh and local backup timers remain configured. GitHub MCP is not part of this update.

## Validation

This patch changes only the Herdr Core service/timer and references to `hc`. Bash syntax was checked; full NixOS evaluation and an end-to-end remote Herdr connection were not tested here.
