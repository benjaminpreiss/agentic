---
status: superseded by ADR-0002
---
# Select NixOS skills with checked-in symlinks

We will keep skills in this monorepo and make the contents of `skills/enabled/` the selection interface for skills installed by NixOS. `skills/available/` holds skills maintained here and skills imported from other authors (including Matt Pocock). A checked-in symlink from `enabled/` to a skill in `available/` enables it; removing the link disables it without deleting the source. Matt Pocock's skills are enabled by default through checked-in links, not through a special Nix option. This avoids maintaining a separate enable list or toggle alongside the directory.

`skills.sh` is a **repo-preparation/import tool**, not a command run during NixOS activation. Imported changes are reviewed and committed before deployment; activation installs from the staged, versioned source rather than downloading mutable upstream content. Once the import replaces the existing pinned `matt-skills` flake input, remove that input and its hardcoded installation so there is only one source of installed skills.

As part of [issue #26](https://github.com/benjaminpreiss/agentic/issues/26), the shared staging operation must include both `skills/available/` and `skills/enabled/`, preserving links and their in-source targets without copying the entire checkout or secrets into the Nix flake source. Installation must reject broken or escaping links clearly and must not overwrite user-managed skills. Tests should cover default-enabled skills, disabling a skill by removing its link, and staged-link validity. The install/update restructuring and the exact `skills.sh` import procedure remain implementation work, not decisions made by this record.
