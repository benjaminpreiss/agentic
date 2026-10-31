# Input: effective rules array from GET /repos/{owner}/{repo}/rules/branches/{branch}.
# Argument: --arg branch <branch name>. Output: one array of {status, message}.
# Effective rules do not expose reviewer identity or App bypass permissions.
. as $rules
| [.[] | select(.type == "pull_request")] as $prs
| ($branch | startswith("agentic/")) as $autonomous
| [
    {status: (if ($prs | length) > 0 then "ok" else "fail" end),
     message: "requires a pull request"},

    # All applicable PR rules must specify squash only; missing method data
    # is unverifiable and therefore fails rather than passing by default.
    (if ($prs | length) == 0 then
      {status: "fail", message: "squash-only merging: no pull-request rule"}
    elif all($prs[]; .parameters.allowed_merge_methods == ["squash"]) then
      {status: "ok", message: "allows squash merging only"}
    else
      {status: "fail", message: "squash-only merging: allowed methods missing or include merge/rebase"}
    end),

    (if $autonomous then
      if any($prs[]; (.parameters.required_approving_review_count // 0) > 0) then
        {status: "warn", message: "requires approvals (autonomous merges may be blocked)"}
      else
        {status: "ok", message: "permits zero-approval PR merges"}
      end
    elif any($prs[]; (.parameters.required_approving_review_count // 0) >= 1) then
      {status: "ok", message: "requires at least one PR approval"}
    else
      {status: "fail", message: "requires at least one PR approval"}
    end),

    (if $autonomous then empty
    elif any($prs[]; .parameters.dismiss_stale_reviews_on_push == true) then
      {status: "ok", message: "dismisses stale approvals after new commits"}
    else
      {status: "fail", message: "must dismiss stale approvals after new commits"}
    end),

    {status: (if any($rules[]; .type == "non_fast_forward") then "ok" else "fail" end),
     message: "blocks force pushes"},
    {status: (if any($rules[]; .type == "deletion") then "ok" else "fail" end),
     message: "blocks deletion"}
  ]
