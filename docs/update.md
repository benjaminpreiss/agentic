# Update and recover agentic NixOS

**Only a host explicitly bootstrapped with the pinned toolkit may use its poller.** An older host does not gain autonomous updates merely because this PR merges. Do not use the disk installer for updates or repairs.

## A new toolkit-managed host

The root-owned target state in `/var/lib/agentic/deployment` contains a selector and known-good revision. Its timer is always enabled:

| Selector | Poll behaviour |
| --- | --- |
| `commit:FULL_SHA` | No fetch, build or switch. Fresh installs start here. |
| `branch:NAME` | Fetches **only that branch**, builds an eligible new tip, then switches. |

The target owns its checkout (`/var/lib/agentic/source`) and private, credential-free machine facts (`/var/lib/agentic/machine`). The selector lives outside fetched source. A candidate branch does not respond to a push to `main`; a pinned candidate never updates automatically. Protect any branch tracked by a production host with reviewed PRs and required checks. A successful build does not prove a safe boot.

To change selection, use the [pinned toolkit's `deploy` or `transition` interface](https://github.com/benjaminpreiss/themoss.net/blob/05f25bf2e700deb55c59882d00e781a1e1583d07/docs/updates.md) from an operator-controlled machine or the root-owned checkout on the target. A branch deployment must use its current pushed tip. Divergent history (such as a squash merge) requires a reviewed **non-destructive transition**; ordinary polling fails closed. The toolkit never runs Disko on this path. If a switch fails, stop the timer, inspect `/var/lib/agentic/deployment/needs-inspection`, the running generation and journal, and recover via console or `nixos-rebuild` rollback before resuming.

GitHub App credentials are not fetched from themoss.net or Nix. Transfer them separately with `scripts/deployment/credentials.sh root@HOST` if they need changing. After a switch, verify Pi/OMP, nono packs, skills, SSH, network and GitHub audit. The former local `apply.sh` performed nono pulls; on toolkit-managed hosts run and verify `nono pull nolabs-ai/pi` and `nono pull nolabs-ai/omp` under the `agentic` user after a reviewed change to their packages.

To update the toolkit itself, propose a PR changing the `themoss` flake input and committed root `flake.lock`, run `bash scripts/test-deployment.sh` and build/test a disposable VM before merging. Each target receives the revision only when its selected branch advances. No runtime `curl | sh` is used. Never put private `machine.nix` or credentials in the committed lock or flake.

## Existing host: remain on the legacy manual path for now

**Do not assume the target currently runs Git commit `f73e8ca`.** The original workflow did not record a revision. [Issue #32](https://github.com/benjaminpreiss/agentic/issues/32) tracks verifying the real running generation and original private lock, then using the toolkit's receipt-less `adopt` operation without reinstalling. That operation requires an evidence file and a matching build; it refuses guesses. A difference between the old `.deployment/flake.lock` and committed root `flake.lock` is a reviewed dependency update, not an automatic replacement.

Until #32's baseline is verified, keep the original `.deployment/`, its `generated/` hardware records, private `flake.lock`, `extra-files/` and `secrets/`. Use the **old** `scripts/update/apply.sh` from the same checkout to manually update an already-installed host. It still stages into the original private `.deployment/` and does not run Disko; do not delete or reset that directory to satisfy the new toolkit. Run `bash scripts/test-stage.sh` before applying. No live host is migrated by merging this PR.

If the old manual switch fails, preserve known-good NixOS generations, inspect via SSH or console, and roll back; never run the destructive toolkit `install` operation as a repair step. Keep off-server backups of private files. The legacy script is retained only so existing hosts continue to work until the separate migration is verified; it is **not** the new host update engine.
