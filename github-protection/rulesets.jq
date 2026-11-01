# Input: detailed rulesets returned by GET /repos/{owner}/{repo}/rulesets/{id}
# with includes_parents=true (the list endpoint selects rulesets for this repo).
# A conservative proof of future coverage: a ~ALL rule covers every branch.
# Exclusions are acceptable for non-agentic targets only if they cannot match
# anything outside refs/heads/agentic/. Other patterns may be valid but are
# reported as unverified rather than being silently assumed to cover all refs.
. as $sets
| def universal($class):
    .enforcement == "active" and .target == "branch"
    and ((.conditions.ref_name.include // []) | index("~ALL") != null)
    and ((.conditions.ref_name.exclude // []) | type == "array")
    and (if $class == "all" then
      (.conditions.ref_name.exclude | length == 0)
    else
      all(.conditions.ref_name.exclude[]; startswith("refs/heads/agentic/"))
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
    (if rule("squash"; "all") then
       {status: "ok", message: "all branch names covered by a squash-only PR rule"}
     else {status: "fail", message: "cannot prove all branches have a squash-only PR rule (~ALL with no exclusions required)"} end),
    (if rule("approval"; "non-agentic") then
       {status: "ok", message: "all non-agentic/* targets require approvals and dismiss stale reviews"}
     else {status: "fail", message: "cannot prove approvals and stale-review dismissal for every non-agentic/* target"} end),
    (if rule("approval"; "all") then
       {status: "warn", message: "universal approval rule may block autonomous agentic/* merges"}
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
