# Recommended branch rulesets

Every branch except `main` is a directly writable work branch. `main` accepts changes through PRs with at least one approval.

| Ruleset | Include | Exclude | Requirements |
|---|---|---|---|
| Common safety | All branches | None | Block force pushes and deletion. Work branches allow direct pushes. |
| Review `main` | The exact `main` branch | None | Require a PR, squash-only merging, at least one approval, and dismiss stale approvals after new commits. Add required CI checks where appropriate. |

Set both rulesets to **Active**. Keep the coding App off their bypass lists.
