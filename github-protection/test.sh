#!/usr/bin/env bash
# Offline policy tests: no GitHub credentials or network access required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
POLICY="$ROOT/github-protection/policy.jq"

check() {
  local branch="$1" rules="$2" expected="$3" results actual
  results="$(jq -c --arg branch "$branch" -f "$POLICY" <<<"$rules")"
  actual="$(jq -c '[.[] | select(.status != "ok") | [.status, .message]]' <<<"$results")"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL %s: expected %s, got %s\n' "$branch" "$expected" "$actual" >&2
    exit 1
  fi
}

protected='[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]'
autonomous='[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":0}},{"type":"non_fast_forward"},{"type":"deletion"}]'
check main "$protected" '[]'
check agentic "$protected" '[]' # Exact agentic is NOT agentic/*.
check 'agentic/release' "$autonomous" '[]'
check 'other/release' "$autonomous" '[["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"]]'
check 'agentic/release' "$protected" '[["warn","requires approvals (autonomous merges may be blocked)"]]'
check main '[]' '[["fail","requires a pull request"],["fail","squash-only merging: no pull-request rule"],["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"],["fail","blocks force pushes"],["fail","blocks deletion"]]'
check main '[{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
check main '[{"type":"pull_request","parameters":{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
# Every applicable PR rule must specify squash, not just one of them.
check main '[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"]}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
# Structural policy: ~ALL must prove future coverage, while approval rules may
# exclude only agentic/* targets. An agentic/* approval is not required.
sets='[{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]}},{"type":"non_fast_forward"},{"type":"deletion"}]},{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":["refs/heads/agentic/*"]}},"bypass_actors":[],"rules":[{"type":"pull_request","parameters":{"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}}]}]'
check_sets() {
  local input="$1" expected="$2" actual
  actual="$(jq -c --argjson app_id 123 -f "$ROOT/github-protection/rulesets.jq" <<<"$input" | jq -c '[.[] | select(.status != "ok") | [.status, .message]]')"
  if [[ "$actual" != "$expected" ]]; then
    printf 'FAIL rulesets: expected %s, got %s\n' "$expected" "$actual" >&2
    exit 1
  fi
}
check_sets "$sets" '[]'
check_sets "$(jq '.[1].conditions.ref_name.exclude = []' <<<"$sets")" '[["warn","universal approval rule may block autonomous agentic/* merges"]]'
check_sets "$(jq '.[0].conditions.ref_name.include = ["refs/heads/main"]' <<<"$sets")" '[["fail","cannot prove all branches have a squash-only PR rule (~ALL with no exclusions required)"],["fail","cannot prove all branch names block force pushes"],["fail","cannot prove all branch names block deletion"]]'
check_sets "$(jq '.[1].conditions.ref_name.exclude = ["refs/heads/main"]' <<<"$sets")" '[["fail","cannot prove approvals and stale-review dismissal for every non-agentic/* target"]]'
check_sets "$(jq 'del(.[0].bypass_actors)' <<<"$sets")" '[["warn","App bypass actors are hidden on at least one active ruleset"]]'
check_sets "$(jq '.[0].bypass_actors = [{"actor_type":"Integration","actor_id":123}]' <<<"$sets")" '[["fail","App appears as a bypass actor in an active ruleset"],["warn","inspect configured bypass actors and role-based bypass rights manually"]]'
printf 'Policy fixtures passed\n'
