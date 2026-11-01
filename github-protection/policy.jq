# Input: effective branch rules; argument: --arg branch <name>.
# agentic/* branches are directly writable work branches. PRs into them are
# optional; GitHub cannot both require PRs and allow ordinary direct pushes.
. as $rules
| [.[] | select(.type == "pull_request")] as $prs
| ($branch | startswith("agentic/")) as $work
| [
    (if $work then
      if ($prs | length) == 0 then
        {status: "ok", message: "permits direct pushes (no PR rule)"}
      else
        {status: "fail", message: "PR rule blocks direct pushes to agentic/*"}
      end
    elif ($prs | length) > 0 then
      {status: "ok", message: "requires a pull request"}
    else
      {status: "fail", message: "requires a pull request"}
    end),

    (if $work then empty
    elif ($prs | length) == 0 then
      {status: "fail", message: "squash-only merging: no pull-request rule"}
    elif all($prs[]; .parameters.allowed_merge_methods == ["squash"]) then
      {status: "ok", message: "allows squash merging only"}
    else
      {status: "fail", message: "squash-only merging: allowed methods missing or include merge/rebase"}
    end),

    (if $work then empty
    elif any($prs[]; (.parameters.required_approving_review_count // 0) >= 1) then
      {status: "ok", message: "requires at least one PR approval"}
    else
      {status: "fail", message: "requires at least one PR approval"}
    end),

    (if $work then empty
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
