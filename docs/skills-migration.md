# Remove the old Matt Pocock skills link

Existing Agentic installations may have a `~/.pi/agent/skills/mattpocock` symlink created by the **previous** NixOS module. The new module installs selected, versioned skills under `~/.pi/agent/skills/agentic`. It **does not remove** the old link or modify other user-managed skills. Leaving the old link in place can expose duplicate skills, including skills disabled in `skills/enabled/`.

## After the non-destructive update (recommended)

First [run the update](update.md) and confirm the new skills are present. Then, **on the server as `agentic`**, inspect the old path before removing anything:

```bash
ls -ld -- ~/.pi/agent/skills/mattpocock ~/.pi/agent/skills/agentic
readlink -- ~/.pi/agent/skills/mattpocock
```

The old path should be a **symlink** pointing to the old pinned Matt skills source in `/nix/store/`; `agentic` should be a separate directory containing the newly installed links. If `mattpocock` is a real directory, points somewhere else, or contains work you want to keep, **stop**: it may be user-managed. Do not delete or recursively remove it.

Only after checking that the `mattpocock` path is the old symlink, unlink that path (not its target):

```bash
rm -- ~/.pi/agent/skills/mattpocock
ls -ld -- ~/.pi/agent/skills/agentic
```

If the path is absent, there is nothing to do. If you cannot unlink it as `agentic`, check ownership of `~/.pi/agent/skills` and use the provider's administrative account for **that single symlink only**; do not recursively change ownership or delete the skills directory. Verify `pi` can discover the desired skills and that the old duplicate no longer appears. If the new skills are missing, leave the old link in place and investigate `systemctl status agentic-skills.service` before cleanup.

You can do the same inspection and unlink **before** updating, but the old skills will be unavailable until the new module activates successfully. No production action is performed by this document.
