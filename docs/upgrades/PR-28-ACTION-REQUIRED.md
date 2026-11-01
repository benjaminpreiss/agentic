# Action required after PR #28: remove the old skills link

Use this guide **once** when updating an Agentic NixOS machine from a version before PR #28. These changes are not a general cleanup policy. The [normal update guide](../update.md) contains the full switch procedure; this page calls out what is different for this PR.

## What changed in this PR

| Before PR #28 | After PR #28 |
| --- | --- |
| `scripts/apply.sh` copied a hand-maintained subset of files. | `scripts/update/apply.sh` and `scripts/install/prepare.sh` share `scripts/stage.sh`; it refreshes declared credential-free sources. |
| Flake, modules and profiles were at the repository root. | Source lives under `nixos/` and is staged into the same `.deployment/` layout as before. |
| The `matt-skills` flake input installed a link at `~/.pi/agent/skills/mattpocock`. | Versioned skills in `skills/available/` are selected by `skills/enabled/` and installed under `~/.pi/agent/skills/agentic`. |

**Do not run the new install script on an existing machine:** it invokes Disko and erases the disk. Do not delete `.deployment/`; its generated machine files and lock file are reused. Neither the update nor the new NixOS service removes the old `mattpocock` link automatically.

## Upgrade from the old checkout

1. On the deployment computer, update the *same* Git checkout with `git pull --ff-only origin main` as described in [update step 1](../update.md#1-update-the-local-repository). Confirm `.deployment/` still contains the original `flake.lock`, generated machine files and target. Check the changed paths if you use custom scripts: the new operator commands live under `scripts/install/`, `scripts/update/`, and `scripts/github/`.
2. Follow [update steps 2–5](../update.md#2-check-the-machine-and-private-deployment-state). Verify `agentic-skills.service` succeeded and the new `~/.pi/agent/skills/agentic` directory contains the selected links. The old `mattpocock` link may now cause duplicates (including skills you disable later); **leave it until the new skills work**.
3. On the server as `agentic`, inspect both paths:

   ```bash
   ls -ld -- ~/.pi/agent/skills/mattpocock ~/.pi/agent/skills/agentic
   readlink -- ~/.pi/agent/skills/mattpocock
   ```

   The old path should be a **symlink** to the prior pinned Matt skills source in `/nix/store/`; `agentic` should be a separate directory with the new links. If the old path is absent, there is nothing to clean up. If it is a real directory or points somewhere else, **stop**: it may be user-managed. Never remove it recursively.
4. **Only after verifying the new skills** and confirming `mattpocock` is the old symlink, unlink that path (not the store target):

   ```bash
   rm -- ~/.pi/agent/skills/mattpocock
   ls -ld -- ~/.pi/agent/skills/agentic
   ```

   If unlinking fails, inspect the parent directory's ownership and have an administrator remove **that one verified symlink only**; do not recursively change ownership. Verify `pi` discovers the desired skills without duplicates.

If you choose to unlink the old symlink **before** updating, the old skills will be unavailable until the new system activates. If the new skills are missing after the switch, retain the old link and inspect `systemctl status agentic-skills.service` before any cleanup. This guide describes operator actions; it runs nothing automatically.
