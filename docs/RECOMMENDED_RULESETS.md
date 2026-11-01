# Recommended branch rulesets

Agents may push directly to `agentic/*`. PRs into those branches are optional and may be merged without owner approval. A PR targeting any other branch requires owner approval under the [policy in issue #5](https://github.com/benjaminpreiss/agentic/issues/5).

| Ruleset | Include | Exclude | Requirements |
|---|---|---|---|
| Common safety | All branches | None | Block force pushes and deletion. Do **not** require a PR here: that would block normal pushes to `agentic/*`. |
| Review other targets | All branches | `agentic/*` | Require a PR, squash-only merging, at least one approval, and dismiss stale approvals after new commits. Add required CI checks where appropriate. |

For the second ruleset, select **All branches** *and then* exclude `agentic/*`; an exclusion alone is not enough. Check whether that exclusion also matches nested names such as `agentic/team/task`. The exact branch `agentic` (without `/`) is **not** excluded. Do not give the coding App bypass rights.

**Limitations:** Direct pushes to `agentic/*` mean PR-only merging cannot be enforced for those targets. One required approval also does **not** guarantee that the reviewer is the owner; that needs a trusted merge gate. The current `github-protection/` audit still assumes PRs are required on every branch and must be updated before it can pass under this revised policy.
