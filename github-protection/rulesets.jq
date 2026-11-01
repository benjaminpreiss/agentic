# Detailed repository and parent rulesets. Only ~DEFAULT_BRANCH (with no
# exclusions) proves protection follows a default-branch rename. Any other
# active PR-rule target is treated as potentially blocking work-branch pushes.
. as $sets
| def default_only:
    .enforcement == "active" and .target == "branch" and
    .conditions.ref_name.include == ["~DEFAULT_BRANCH"] and
    .conditions.ref_name.exclude == [];
  def all_branches:
    .enforcement == "active" and .target == "branch" and
    .conditions.ref_name.include == ["~ALL"] and
    .conditions.ref_name.exclude == [];
  def has_rule($kind):
    any($sets[]; all_branches and any(.rules[]?; .type == $kind));
  [
    (if any($sets[]; default_only and any(.rules[]?;
         .type == "pull_request" and .parameters.allowed_merge_methods == ["squash"])) then
       {status:"ok", message:"default branch has a squash-only PR rule"}
     else {status:"fail", message:"cannot prove default branch has a squash-only PR rule targeting only the default branch"} end),
    (if any($sets[]; default_only and any(.rules[]?;
         .type == "pull_request" and
         (.parameters.required_approving_review_count // 0) >= 1 and
         .parameters.dismiss_stale_reviews_on_push == true)) then
       {status:"ok", message:"default branch requires approval and stale-review dismissal"}
     else {status:"fail", message:"cannot prove default branch requires approval and stale-review dismissal"} end),
    (if any($sets[]; .enforcement == "active" and .target == "branch" and
         any(.rules[]?; .type == "pull_request") and (default_only | not)) then
       {status:"fail", message:"PR rule outside default branch may block direct pushes to work branches"}
     else {status:"ok", message:"no PR rules target work branches"} end),
    (if has_rule("non_fast_forward") then
       {status:"ok", message:"all branch names block force pushes"}
     else {status:"fail", message:"cannot prove all branch names block force pushes"} end),
    (if has_rule("deletion") then
       {status:"ok", message:"all branch names block deletion"}
     else {status:"fail", message:"cannot prove all branch names block deletion"} end),
    (if any($sets[]; .enforcement == "active" and
        any(.bypass_actors[]?; .actor_type == "Integration" and .actor_id == $app_id)) then
       {status:"fail", message:"App appears as a bypass actor in an active ruleset"}
     else empty end),
    (if any($sets[]; .enforcement == "active" and (has("bypass_actors") | not)) then
       {status:"warn", message:"App bypass actors are hidden on at least one active ruleset"}
     else empty end),
    (if any($sets[]; .enforcement == "active" and ((.bypass_actors // []) | length > 0)) then
       {status:"warn", message:"inspect configured bypass actors and role-based bypass rights manually"}
     else empty end)
  ]
