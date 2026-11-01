# Input: detailed rulesets returned by GET /repos/{owner}/{repo}/rulesets/{id}
# with includes_parents=true (the list endpoint selects rulesets for this repo).
# The common safety rule covers ~ALL. GitHub also returns include: [] for an
# all-branches rule with exclusions; accept that shape only for non-agentic
# targets when every exclusion has the literal refs/heads/agentic/ prefix.
# Other patterns are unproven. Effective branch samples still run separately.
. as $sets
| def universal($class):
    .enforcement == "active" and .target == "branch"
    and ((.conditions.ref_name.include // []) | type == "array")
    and ((.conditions.ref_name.exclude // []) | type == "array")
    and (if $class == "all" then
      ((.conditions.ref_name.include | index("~ALL")) != null)
      and (.conditions.ref_name.exclude | length == 0)
    else
      (((.conditions.ref_name.include | index("~ALL")) != null)
       or ((.conditions.ref_name.include | length == 0) and (.conditions.ref_name.exclude | length > 0)))
      and all(.conditions.ref_name.exclude[]; startswith("refs/heads/agentic/"))
    end);
  def rule($kind; $class):
    any($sets[]; universal($class) and any(.rules[]?;
      if $kind == "squash" then
        .type == "pull_request" and .parameters.allowed_merge_methods == ["squash"]
      elif $kind == "approval" then
        .type == "pull_request" and
        (.parameters.required_approving_review_count // 0) >= 1 and
        .parameters.dismiss_stale_reviews_on_push == true
      else .type == $kind end));
  [
    (if rule("squash"; "non-agentic") then
       {status: "ok", message: "non-agentic/* targets covered by a squash-only PR rule"}
     else {status: "fail", message: "cannot prove squash-only PR coverage for non-agentic/* targets"} end),
    (if rule("approval"; "non-agentic") then
       {status: "ok", message: "all non-agentic/* targets require approvals and dismiss stale reviews"}
     else {status: "fail", message: "cannot prove approvals and stale-review dismissal for every non-agentic/* target"} end),
    (if any($sets[]; universal("all") and any(.rules[]?; .type == "pull_request")) then
       {status: "fail", message: "all-branches PR rule blocks direct pushes to agentic/*"}
     else empty end),
    (if any($sets[]; .enforcement == "active" and .target == "branch" and
        (.conditions.ref_name.include == []) and
        all(.conditions.ref_name.exclude[]?; startswith("refs/heads/agentic/")) and
        (.conditions.ref_name.exclude | length > 0)) then
       {status: "warn", message: "GitHub reports include: [] for an all-except-agentic/* rule; confirm effective rules on representative branches"}
     else empty end),
    (if rule("non_fast_forward"; "all") then
       {status: "ok", message: "all branch names block force pushes"}
     else {status: "fail", message: "cannot prove all branch names block force pushes"} end),
    (if rule("deletion"; "all") then
       {status: "ok", message: "all branch names block deletion"}
     else {status: "fail", message: "cannot prove all branch names block deletion"} end),
    (if any($sets[]; .enforcement == "active" and
        any(.bypass_actors[]?; .actor_type == "Integration" and .actor_id == $app_id)) then
       {status: "fail", message: "App appears as a bypass actor in an active ruleset"}
     else empty end),
    (if any($sets[]; .enforcement == "active" and (has("bypass_actors") | not)) then
       {status: "warn", message: "App bypass actors are hidden on at least one active ruleset"}
     else empty end),
    (if any($sets[]; .enforcement == "active" and ((.bypass_actors // []) | length > 0)) then
       {status: "warn", message: "inspect configured bypass actors and role-based bypass rights manually"}
     else empty end)
  ]
