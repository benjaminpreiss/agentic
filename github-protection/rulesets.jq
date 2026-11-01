# Input: detailed rulesets applicable to the repository.
# Only an explicit refs/heads/main PR rule is accepted for the review policy.
# Other valid patterns are conservatively unproven; no work branch may be
# subject to a pull_request rule, since it would block direct pushes.
. as $sets
| def active_branch: .enforcement == "active" and .target == "branch";
  def all_branches:
    active_branch and .conditions.ref_name.include == ["~ALL"]
    and .conditions.ref_name.exclude == [];
  def main_only:
    active_branch and .conditions.ref_name.include == ["refs/heads/main"]
    and .conditions.ref_name.exclude == [];
  def main_pr($kind):
    any($sets[]; main_only and any(.rules[]?;
      .type == "pull_request" and
      (if $kind == "squash" then .parameters.allowed_merge_methods == ["squash"]
       else (.parameters.required_approving_review_count // 0) >= 1 and
            .parameters.dismiss_stale_reviews_on_push == true end)));
  [
    (if main_pr("squash") then
       {status: "ok", message: "main is covered by a squash-only PR rule"}
     else {status: "fail", message: "cannot prove main has a squash-only PR rule targeting only main"} end),
    (if main_pr("approval") then
       {status: "ok", message: "main requires approval and dismisses stale reviews"}
     else {status: "fail", message: "cannot prove main requires approval and stale-review dismissal"} end),
    (if any($sets[]; active_branch and (main_only | not) and
        any(.rules[]?; .type == "pull_request")) then
       {status: "fail", message: "PR rule outside main may block direct pushes to work branches"}
     else {status: "ok", message: "no PR rule targets work branches"} end),
    (if any($sets[]; all_branches and any(.rules[]?; .type == "non_fast_forward")) then
       {status: "ok", message: "all branch names block force pushes"}
     else {status: "fail", message: "cannot prove all branch names block force pushes"} end),
    (if any($sets[]; all_branches and any(.rules[]?; .type == "deletion")) then
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
