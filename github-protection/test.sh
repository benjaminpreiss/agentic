#!/usr/bin/env bash
# Offline policy tests: no GitHub credentials or network access required.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
for script in check.sh github-api.sh ci.sh; do bash -n "$ROOT/github-protection/$script"; done

check() {
  local branch="$1" rules="$2" expected="$3" actual
  actual="$(jq -c --arg branch "$branch" -f "$ROOT/github-protection/policy.jq" <<<"$rules" | jq -c '[.[] | select(.status != "ok") | [.status, .message]]')"
  [[ "$actual" == "$expected" ]] || { printf 'FAIL %s: expected %s, got %s\n' "$branch" "$expected" "$actual" >&2; exit 1; }
}
protected='[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]'
work='[{"type":"non_fast_forward"},{"type":"deletion"}]'
check main "$protected" '[]'
check agentic "$protected" '[]' # Exact agentic is not agentic/*.
check 'agentic/release' "$work" '[]'
check 'agentic/release' "$protected" '[["fail","PR rule blocks direct pushes to agentic/*"]]'
check 'other/release' "$work" '[["fail","requires a pull request"],["fail","squash-only merging: no pull-request rule"],["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"]]'
check main '[]' '[["fail","requires a pull request"],["fail","squash-only merging: no pull-request rule"],["fail","requires at least one PR approval"],["fail","must dismiss stale approvals after new commits"],["fail","blocks force pushes"],["fail","blocks deletion"]]'
check main '[{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'
# Every applicable PR rule must specify squash, not just one of them.
check main '[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}},{"type":"pull_request","parameters":{"allowed_merge_methods":["merge"]}},{"type":"non_fast_forward"},{"type":"deletion"}]' '[["fail","squash-only merging: allowed methods missing or include merge/rebase"]]'

check_sets() {
  local input="$1" expected="$2" actual
  actual="$(jq -c --argjson app_id 123 -f "$ROOT/github-protection/rulesets.jq" <<<"$input" | jq -c '[.[] | select(.status != "ok") | [.status, .message]]')"
  [[ "$actual" == "$expected" ]] || { printf 'FAIL rulesets: expected %s, got %s\n' "$expected" "$actual" >&2; exit 1; }
}
# GitHub's actual all-except-agentic/* API response has include: [] with an
# explicit exclusion. It applies to main and hypothetical other targets.
sets='[{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":["~ALL"],"exclude":[]}},"bypass_actors":[],"rules":[{"type":"non_fast_forward"},{"type":"deletion"}]},{"target":"branch","enforcement":"active","conditions":{"ref_name":{"include":[],"exclude":["refs/heads/agentic/*"]}},"bypass_actors":[],"rules":[{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"],"required_approving_review_count":1,"dismiss_stale_reviews_on_push":true}}]}]'
implicit='[["warn","GitHub reports include: [] for an all-except-agentic/* rule; confirm effective rules on representative branches"]]'
check_sets "$sets" "$implicit"
check_sets "$(jq '.[1].conditions.ref_name.include = ["~ALL"]' <<<"$sets")" '[]'
check_sets "$(jq '.[1].conditions.ref_name.exclude = ["refs/heads/main"]' <<<"$sets")" '[["fail","cannot prove squash-only PR coverage for non-agentic/* targets"],["fail","cannot prove approvals and stale-review dismissal for every non-agentic/* target"]]'
check_sets "$(jq '.[0].rules += [{"type":"pull_request","parameters":{"allowed_merge_methods":["squash"]}}]' <<<"$sets")" '[["fail","all-branches PR rule blocks direct pushes to agentic/*"],["warn","GitHub reports include: [] for an all-except-agentic/* rule; confirm effective rules on representative branches"]]'
check_sets "$(jq 'del(.[0].bypass_actors)' <<<"$sets")" '[["warn","GitHub reports include: [] for an all-except-agentic/* rule; confirm effective rules on representative branches"],["warn","App bypass actors are hidden on at least one active ruleset"]]'
check_sets "$(jq '.[0].bypass_actors = [{"actor_type":"Integration","actor_id":123}]' <<<"$sets")" '[["warn","GitHub reports include: [] for an all-except-agentic/* rule; confirm effective rules on representative branches"],["fail","App appears as a bypass actor in an active ruleset"],["warn","inspect configured bypass actors and role-based bypass rights manually"]]'
# A branch tip with no observed/required CI must emit only the 0/0 warning;
# the old jq JSON output produced a spurious `not observed on tip: ""` warning.
(
  source "$ROOT/github-protection/ci.sh"
  API=https://api.github.com token=unused
  warnings=()
  ok() { :; }
  warn() { warnings+=("$1"); }
  api() {
    STATUS=200
    case "$2" in
      */check-runs\?*) BODY='{"check_runs":[]}' ;;
      */statuses\?*) BODY='[]' ;;
      *) return 1 ;;
    esac
  }
  check_main_ci owner/repo 0000000000000000000000000000000000000000 '[{"type":"required_status_checks","parameters":{"required_status_checks":[]}}]'
  [[ "${#warnings[@]}" == 1 && "${warnings[0]}" == 'main CI checks required/available: 0/0' ]] || {
    printf 'FAIL CI warnings: %s\n' "${warnings[*]}" >&2; exit 1;
  }
)
printf 'Policy fixtures passed\n'
