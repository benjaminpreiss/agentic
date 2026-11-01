#!/usr/bin/env bash
# Offline policy fixtures; no credentials or network required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in check.sh github-api.sh ci.sh; do bash -n "$ROOT/github-protection/$script"; done
check() {
  local branch="$1" rules="$2" expected="$3" actual
  actual="$(jq -c --arg branch "$branch" --arg default_branch trunk -f "$ROOT/github-protection/policy.jq" <<<"$rules" | jq -c '[.[] | select(.status != "ok") | [.status,.message]]')"
  [[ "$actual" == "$expected" ]] || { printf 'FAIL %s: expected %s, got %s\n' "$branch" "$expected" "$actual" >&2; exit 1; }
}
protected='[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]'
work='[{"type":"non_fast_forward"},{"type":"deletion"}]'
check trunk "$protected" '[]'
for branch in feature/test main agentic agentic/release; do
  check "$branch" "$work" '[]'
  check "$branch" "$protected" '[["fail","work branch permits direct pushes (no PR rule)"]]'
done
check feature/test '[]' '[["fail","blocks force pushes"],["fail","blocks deletion"]]'
check trunk "$work" '[["fail","requires a pull request"],["fail","squash-only merging: no pull-request rule"],["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"]]'
check trunk '[]' '[["fail","requires a pull request"],["fail","squash-only merging: no pull-request rule"],["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"],["fail","blocks force pushes"],["fail","blocks deletion"]]'
check trunk '[{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
check trunk '[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"]}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
sets='[{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"non_fast_forward"},{"type":"deletion"}]},{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~DEFAULT_BRANCH"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}}]}]'
check_sets() {
  local input="$1" expected="$2" actual
  actual="$(jq -c --argjson app_id 123 -f "$ROOT/github-protection/rulesets.jq" <<<"$input" | jq -c '[.[] | select(.status != "ok") | [.status,.message]]')"
  [[ "$actual" == "$expected" ]] || { printf 'FAIL rulesets: expected %s, got %s\n' "$expected" "$actual" >&2; exit 1; }
}
check_sets "$sets" '[]'
check_sets "$(jq '.[1].conditions.ref_name.include = ["refs/heads/main"]' <<<"$sets")" '[["fail","cannot prove default branch has a squash-only PR rule targeting only the default branch"],["fail","cannot prove default branch requires approval and stale-review dismissal"],["fail","PR rule outside default branch may block direct pushes to work branches"]]'
check_sets "$(jq '.[1].conditions.ref_name.include = ["~ALL"]' <<<"$sets")" '[["fail","cannot prove default branch has a squash-only PR rule targeting only the default branch"],["fail","cannot prove default branch requires approval and stale-review dismissal"],["fail","PR rule outside default branch may block direct pushes to work branches"]]'
check_sets "$(jq '.[0].conditions.ref_name.include = ["refs/heads/main"]' <<<"$sets")" '[["fail","cannot prove all branch names block force pushes"],["fail","cannot prove all branch names block deletion"]]'
check_sets "$(jq '.[1].rules[0].parameters.dismiss_stale_reviews_on_push = false' <<<"$sets")" '[["fail","cannot prove default branch requires approval and stale-review dismissal"]]'
check_sets "$(jq '.[1].rules[0].parameters.allowed_merge_methods = ["merge"]' <<<"$sets")" '[["fail","cannot prove default branch has a squash-only PR rule targeting only the default branch"]]'
check_sets "$(jq 'del(.[0].bypass_actors)' <<<"$sets")" '[["warn","App bypass actors are hidden on at least one active ruleset"]]'
check_sets "$(jq '.[0].bypass_actors = [{"actor_type":"Integration","actor_id":123}]' <<<"$sets")" '[["fail","App appears as a bypass actor in an active ruleset"],["warn","inspect configured bypass actors and role-based bypass rights manually"]]'
# No required/observed checks should not report a required context named "".
(
  source "$ROOT/github-protection/ci.sh"
  API=https://api.github.com token=unused
  warnings=()
  ok() { :; }
  warn() { warnings+=("$1"); }
  api() { STATUS=200; case "$2" in */check-runs\?*) BODY='{"check_runs":[]}' ;; */statuses\?*) BODY='[]' ;; *) return 1 ;; esac; }
  check_main_ci owner/repo 0000000000000000000000000000000000000000 '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]'
  [[ "${#warnings[@]}" == 1 && "${warnings[0]}" == 'default branch CI checks required/available: 0/0' ]] || {
    printf 'FAIL CI warnings: %s\n' "${warnings[*]}" >&2; exit 1;
  }
)
printf 'Policy fixtures passed\n'
