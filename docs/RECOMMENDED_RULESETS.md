# Recommended GitHub branch rulesets

Use **two active branch rulesets per repository** accessible to the coding App. Configure them in **Settings → Rules → Rulesets → New branch ruleset**. This layout reflects the [target-branch policy in issue #5](https://github.com/benjaminpreiss/agentic/issues/5): a PR's **base**, not its source, determines whether owner approval is needed.

| Ruleset | Targets | Rules |
|---|---|---|
| **Common protection** | All branches (`~ALL`), **no exclusions** | Require a pull request; permit **squash only**; block force pushes (`non_fast_forward`) and deletion (`deletion`). Use **zero required approvals** in this rule. Add required CI checks if they apply to all targets. |
| **Review outside `agentic/*`** | All branches (`~ALL`), excluding only refs within `refs/heads/agentic/` (for single-level branch names, the UI pattern `agentic/*`) | Require **at least one approval** and **dismiss stale approvals on new commits** in the same pull-request rule. |

Set both to **Active**, not Evaluate or Disabled. Do not grant the coding App bypass rights. Review every existing repository and organization ruleset too: rules stack, so an older approval requirement applying to `agentic/*` can still block autonomous merges, and a bypass can defeat protections. The exact branch `agentic` is **not** `agentic/*`: if it still exists, it requires approval like `main` and every other non-`agentic/*` target. Retire that exact branch after migrating its dependencies.

## Why not a third `main` ruleset?

`main` and all other targets outside `agentic/*` have the **same approval policy**. A `main`-specific rule is only needed if `main` has additional requirements, such as different required CI checks. Check names may differ between repositories; select checks that actually run on the relevant PRs. The audit's `main`-tip CI count is only a snapshot, not proof that a PR's checks have passed.

## Matching and audit limitations

The audit's [ruleset coverage evaluator](../github-protection/rulesets.jq) accepts these `~ALL` shapes as a **sufficient** proof of coverage for future branch names. An alternative valid ruleset configuration may be reported as *unproven* rather than silently passed. Its approval-rule exclusions must have the literal `refs/heads/agentic/` prefix; the common rule must have **no exclusions**. In GitHub's UI, verify how the exclusion matches names with additional slashes (for example `agentic/team/task`); do not assume a displayed `agentic/*` pattern covers nested names. Test representative targets after saving each ruleset.

A native required-approval count **cannot require approval from benjaminpreiss specifically**. It also cannot establish whether an App can merge *after* someone else approves. Effective branch rules may hide bypass actors from an App without sufficient permissions. This layout is **not a substitute** for the trusted merge gate and App-credential positive/negative tests required by issue #5. Do not claim named-reviewer enforcement based on a passing audit.

## Verify

1. Run the read-only audit locally with the configured App credentials: `bash github-protection/check.sh`. It checks **every repository in that installation**, not every installation of the App. Use `--all-branches` for the slower exhaustive scan of existing branch rules.
2. On the deployed server, read the last cached findings without sudo: `agentic-github-protection-report`. An administrator can request a fresh run with `sudo systemctl start agentic-github-protection-audit.service`. A ❌ finding fails the service; warnings alone do not.
3. With disposable PRs and the **actual App credentials**, test an autonomous merge into `agentic/*`, rejected merges into `main` and another non-`agentic/*` target without owner approval, and approvals that become stale after a new commit. Verify bypass permissions separately with an administrator. Do not use production PRs for destructive tests.

See [GitHub App setup](../AGENTIC_GITHUB_SETUP.md) for credential handling, audit behavior, and the remaining enforcement caveats.
