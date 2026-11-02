# Action required for agentic toolkit adoption (PR #30)

**Do not run the new fresh installer on an existing host.** Merging this PR changes no server. Existing hosts retain `scripts/update/apply.sh` and their original private `.deployment/` until [issue #32](https://github.com/benjaminpreiss/agentic/issues/32) verifies the actual running generation and uses the receipt-less toolkit `adopt` path.

Before any existing-host migration:

1. Back up the whole original `.deployment/` and `secrets/` off-host. Never commit them or replace `generated/{machine.nix,facter.json}`.
2. Compare the host's private `.deployment/flake.lock` with the new committed root `flake.lock`. Differences are a **reviewed dependency upgrade**; do not silently switch an existing machine to the new lock.
3. Verify the active NixOS generation and original machine facts. `f73e8ca` is an operator-reported candidate, *not* a recorded host revision. If uncertain, use a reviewed non-destructive switch to establish a known baseline; never edit state by guess or rerun Disko.
4. Only after successful adoption and validation select a tracked branch. Fresh toolkit installs begin pinned to a commit; timer invocations before adoption fail closed.

For a new host, follow [install](../install.md). Run `bash scripts/test-deployment.sh` and test a disposable VM first. The workflow template in `workflow-templates/deployment-checks.yml` must be reviewed and moved to `.github/workflows/` on the PR branch for GitHub to execute it.
