# Recommended branch rulesets

Create **two active branch rulesets** in each repository where the GitHub App is installed:

| Ruleset | Include | Exclude | Requirements |
|---|---|---|---|
| Common protection | All branches | None | Require a PR, squash-only merging, block force pushes and deletion. Zero required approvals here. |
| Review outside `agentic/*` | All branches | `agentic/*` | At least one approval; dismiss stale approvals when new commits are pushed. |

An exclusion alone is **not** enough: the second ruleset must include **All branches** and then exclude `agentic/*`. `main` needs no separate ruleset unless it has additional requirements. Check that the exclusion also matches any nested names you use, such as `agentic/team/task`, and do not grant the coding App bypass rights.

A required approval count does **not** ensure that the approval came from the repository owner. That still needs the trusted merge gate described in [issue #5](https://github.com/benjaminpreiss/agentic/issues/5).
