# Update an agentic NixOS host

> **Never use `install` to repair an existing host:** it invokes Disko. Merging this PR does not change a live machine.

First determine **which path the host uses**:

| Host | Update path |
| --- | --- |
| Bootstrapped with the pinned themoss.net toolkit | Root-owned checkout; target polls its selected reference. |
| Installed before toolkit adoption | Existing **manual** `.deployment/` update until [#32](https://github.com/benjaminpreiss/agentic/issues/32) verifies migration. |

## Toolkit-managed host: choose what it follows

- 🔒 **`commit:FULL_SHA`:** pinned. The timer fires, but does *not* fetch, build or switch. New installs start here.
- 🔎 **`branch:NAME`:** checks *only that branch*. A new eligible tip is built before switching. `branch:candidate` ignores pushes to `main`.

The selector and known-good revision live in `/var/lib/agentic/deployment`, **outside fetched source**. The target has a root-owned checkout in `/var/lib/agentic/source` and private machine facts in `/var/lib/agentic/machine`. Protect any production branch with reviewed PRs and required checks; a successful build does not prove a safe boot.

**Branch selection is not yet a public `moss` command.** The CLI supports `machine plan` and `machine apply` for a host *already tracking a branch*, but fresh bootstrap pins a commit. Keep a new host pinned until themoss.net exposes a reviewed operator transition; do not call its private `packages/cli/bin/machine/deploy.sh` directly or edit selector state. A divergent branch (such as after a squash merge) must still require an explicit, non-destructive transition. See the [pinned toolkit's machine guide](https://github.com/benjaminpreiss/themoss.net/blob/18ab6e8da7d8ff828cf9e9188221d3d2fcde830c/packages/cli/src/machine/README.md).

### Failure or recovery

1. **Fetch, check or build failed?** No switch or state advance occurred; diagnose before retrying.
2. **Switch started, then failed?** Stop `themoss-update.timer`. Inspect `/var/lib/agentic/deployment/needs-inspection`, `journalctl -u themoss-update`, the active system and `nixos-rebuild list-generations`. Use SSH or the console to recover/roll back; reconcile state *before* restarting the timer.
3. **Secrets or user-managed tools changed?** The poller never uploads GitHub App keys. Transfer them separately with `bash scripts/deployment/credentials.sh root@HOST`. After a reviewed change, verify SSH, networking, Pi/OMP, skills, GitHub audit and nono packs. The former manual updater ran `nono pull nolabs-ai/pi` and `nono pull nolabs-ai/omp`; on toolkit-managed hosts, run/verify these as `agentic` when those packs need updating.

### Update the toolkit pin

Propose a PR changing the `themoss` flake input and **committed root `flake.lock`**. Run `bash scripts/test-deployment.sh` and test a disposable VM before merging. Each branch-tracking target receives the change only when *its selected branch* advances. No runtime `curl | sh` or private credential is staged.

## Existing host: keep the manual path for now

The original deployment did **not** record a Git revision. `f73e8ca` is an operator-reported candidate, not a verified running baseline. [#32](https://github.com/benjaminpreiss/agentic/issues/32) will compare the actual generation, the old private `.deployment/flake.lock` and preserved machine files, then use the toolkit's receipt-less `adopt` path. Any difference between private and committed locks is a **reviewed dependency update**, not an automatic replacement.

Until then:

1. Back up and retain the original private `.deployment/` (including `generated/`, `extra-files/`, target and lock) plus `secrets/` **off-host**.
2. From the *same checkout*, run `bash scripts/test-stage.sh` and `bash scripts/github/test-configure-git-credentials.sh`.
3. Run `bash scripts/update/apply.sh` for a manual non-destructive update. It stages into the old private deployment and does not run Disko. Preserve known-good generations if switching fails; use the console, not the installer, to recover.

The legacy script remains solely to keep existing hosts operable until #32. **Do not infer a revision, delete `.deployment/` or enable branch polling on one merely because this PR merges.**
