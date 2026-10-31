#!/usr/bin/env bash
# Read-only GitHub App installation branch protection audit.
set -euo pipefail
umask 077

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="$ROOT/secrets/github-app"
API=https://api.github.com
for cmd in curl jq openssl date base64; do command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 2; }; done
[[ -r "$SECRETS/app.env" ]] || { echo 'ERROR: missing secrets/github-app/app.env' >&2; exit 2; }
# Read only expected literal numeric settings; never execute an env file as shell code.
read_setting() {
  local value
  value="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$SECRETS/app.env" | tail -n 1 | tr -d '\r')"
  value="${value%\"}"; value="${value#\"}"
  printf '%s' "$value"
}
APP_ID="$(read_setting GITHUB_APP_ID)"
INSTALL_ID="$(read_setting GITHUB_APP_INSTALLATION_ID)"
[[ "$APP_ID" =~ ^[0-9]+$ && "$INSTALL_ID" =~ ^[0-9]+$ ]] || { echo 'ERROR: expected numeric GITHUB_APP_ID and GITHUB_APP_INSTALLATION_ID' >&2; exit 2; }
KEY="$SECRETS/private-key.pem"
[[ -f "$KEY" && -r "$KEY" ]] || { echo 'ERROR: missing active private-key.pem' >&2; exit 2; }
# Symlink must resolve to a file inside the secrets directory; reject escapes.
REAL_KEY="$(cd -P "$(dirname "$KEY")" && realpath "$KEY")"
REAL_DIR="$(cd -P "$SECRETS" && pwd)"
case "$REAL_KEY" in "$REAL_DIR"/*) ;; *) echo 'ERROR: active key must resolve inside secrets/github-app' >&2; exit 2;; esac

b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
unsigned="$header.$payload"
signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$REAL_KEY" | b64url)" || { echo 'ERROR: could not sign JWT' >&2; exit 2; }
jwt="$unsigned.$signature"

# No tokens or request credentials written to disk; curl errors stay redacted.
BODY=''; STATUS=''
api() {
  local method="$1" url="$2" token="$3" result
  result="$(curl --silent --show-error --max-time 30 --request "$method" \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --header "Authorization: Bearer $token" \
    --write-out $'\n%{http_code}' "$url")" || return 1
  STATUS="${result##*$'\n'}"
  BODY="${result%$'\n'*}"
  [[ "$STATUS" =~ ^[0-9][0-9][0-9]$ ]] || return 1
}
api POST "$API/app/installations/$INSTALL_ID/access_tokens" "$jwt" || { echo 'ERROR: token request failed' >&2; exit 2; }
[[ "$STATUS" == 201 ]] || { echo "ERROR: installation token request HTTP $STATUS" >&2; exit 2; }
token="$(jq -er '.token | select(type=="string" and length>0)' <<<"$BODY")" || { echo 'ERROR: installation token missing' >&2; exit 2; }
unset jwt unsigned signature

# Loop over all installation pages, streaming repository identifiers (never tokens).
repos=()
page=1
while :; do
  api GET "$API/installation/repositories?per_page=100&page=$page" "$token" || { echo 'ERROR: repository listing failed' >&2; exit 2; }
  [[ "$STATUS" == 200 ]] || { echo "ERROR: listing repositories HTTP $STATUS" >&2; exit 2; }
  count="$(jq -er '.repositories | arrays | length' <<<"$BODY")" || { echo 'ERROR: unexpected repositories response' >&2; exit 2; }
  while IFS= read -r repo; do [[ -z "$repo" ]] || repos+=("$repo"); done < <(jq -r '.repositories[].full_name' <<<"$BODY")
  ((count < 100)) && break
  ((page+=1))
  ((page < 1000)) || { echo 'ERROR: too many pagination pages' >&2; exit 2; }
done
printf 'GitHub App installation %s: %s repositories\nRead-only audit; no GitHub settings are changed.\n\n' "$INSTALL_ID" "${#repos[@]}"
failures=0
warnings=0
passed=0
ok()   { printf '  ✅ %s\n' "$1"; ((passed+=1)); }
warn() { printf '  ⚠️  %s\n' "$1"; ((warnings+=1)); }
fail() { printf '  ❌ %s\n' "$1"; ((failures+=1)); }

# The GitHub branch-rules API includes applicable rules from repository and
# organization rulesets. It does not prove whether this App has bypass rights.
for repo in "${repos[@]}"; do
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'ERROR: invalid repository identifier' >&2; exit 2; }
  printf '\n📦 %s\n' "$repo"

  for branch in main agentic; do
    printf '  ── %s ──\n' "$branch"
    if ! api GET "$API/repos/$repo/branches/$branch" "$token"; then
      fail "$branch exists: API transport error"
      continue
    fi
    if [[ "$STATUS" == 404 ]]; then
      fail "$branch exists: branch not found"
      continue
    elif [[ "$STATUS" != 200 ]]; then
      fail "$branch exists: HTTP $STATUS"
      continue
    fi
    ok "$branch exists"
    branch_sha="$(jq -r '.commit.sha // empty' <<<"$BODY")"

    if ! api GET "$API/repos/$repo/rules/branches/$branch?per_page=100" "$token"; then
      fail "$branch protection rules: API transport error"
      continue
    elif [[ "$STATUS" != 200 ]]; then
      fail "$branch protection rules: HTTP $STATUS"
      continue
    elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
      fail "$branch protection rules: invalid API response"
      continue
    fi

    if jq -e 'any(.[]; .type=="pull_request")' >/dev/null <<<"$BODY"; then
      ok "$branch requires a pull request"
    else
      fail "$branch requires a pull request"
    fi

    # Squash-only is a property of the effective pull_request rule(s) for
    # this branch, NOT a repository-wide restriction. Multiple applicable
    # rules must all be restrictive; absent method data is unverifiable.
    pr_rule_count="$(jq '[.[] | select(.type=="pull_request")] | length' <<<"$BODY")"
    if ((pr_rule_count == 0)); then
      fail "$branch squash-only merging: no pull-request rule"
    elif jq -e '
      [.[] | select(.type=="pull_request")] |
      all(.[];
        (.parameters.allowed_merge_methods | type) == "array" and
        (.parameters.allowed_merge_methods | length) == 1 and
        .parameters.allowed_merge_methods[0] == "squash"
      )
    ' >/dev/null <<<"$BODY"; then
      ok "$branch allows squash merging only"
    else
      fail "$branch squash-only merging: allowed methods missing or include merge/rebase"
    fi

    if [[ "$branch" == main ]]; then
      if jq -e '[.[] | select(.type=="pull_request") | (.parameters.required_approving_review_count // 0)] | any(.>=1)' >/dev/null <<<"$BODY"; then
        ok 'main requires at least one PR approval'
      else
        fail 'main requires at least one PR approval'
      fi
    else
      if jq -e '[.[] | select(.type=="pull_request") | (.parameters.required_approving_review_count // 0)] | any(.>0)' >/dev/null <<<"$BODY"; then
        fail 'agentic requires approvals (autonomous merges need zero)'
      else
        ok 'agentic permits zero-approval PR merges'
      fi
    fi

    if jq -e 'any(.[]; .type=="non_fast_forward")' >/dev/null <<<"$BODY"; then
      ok "$branch blocks force pushes"
    else
      fail "$branch blocks force pushes"
    fi
    if jq -e 'any(.[]; .type=="deletion")' >/dev/null <<<"$BODY"; then
      ok "$branch blocks deletion"
    else
      fail "$branch blocks deletion"
    fi
    # CI coverage: selected required contexts / distinct contexts observed on
    # the branch tip (check-runs plus commit statuses). This is NOT a complete
    # inventory of all workflows that could run on future pull requests.
    required_names="$(jq -c '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]? | (.context // empty)] | unique' <<<"$BODY")"
    required_count="$(jq 'length' <<<"$required_names")"
    available_names='[]'
    ci_error=''
    if [[ ! "$branch_sha" =~ ^[0-9a-fA-F]{40}$ ]]; then
      ci_error='branch tip SHA was not available'
    else
      # GitHub Check Runs API: first 100 check runs per page, paginated.
      page=1
      while :; do
        if ! api GET "$API/repos/$repo/commits/$branch_sha/check-runs?per_page=100&page=$page" "$token"; then
          ci_error='check-runs request failed'; break
        elif [[ "$STATUS" != 200 ]]; then
          ci_error="check-runs HTTP $STATUS"; break
        elif ! jq -e '.check_runs | type == "array"' >/dev/null <<<"$BODY"; then
          ci_error='invalid check-runs response'; break
        fi
        names="$(jq -c '[.check_runs[].name | select(type=="string")] | unique' <<<"$BODY")"
        available_names="$(jq -cn --argjson a "$available_names" --argjson b "$names" '$a + $b | unique')"
        count="$(jq '.check_runs | length' <<<"$BODY")"
        ((count < 100)) && break
        ((page+=1))
        if ((page > 50)); then ci_error='check-runs pagination limit exceeded'; break; fi
      done
      # Classic commit status contexts are separate from check runs.
      if [[ -z "$ci_error" ]]; then
        page=1
        while :; do
          if ! api GET "$API/repos/$repo/commits/$branch_sha/statuses?per_page=100&page=$page" "$token"; then
            ci_error='commit statuses request failed'; break
          elif [[ "$STATUS" != 200 ]]; then
            ci_error="commit statuses HTTP $STATUS"; break
          elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
            ci_error='invalid commit statuses response'; break
          fi
          names="$(jq -c '[.[].context | select(type=="string")] | unique' <<<"$BODY")"
          available_names="$(jq -cn --argjson a "$available_names" --argjson b "$names" '$a + $b | unique')"
          count="$(jq 'length' <<<"$BODY")"
          ((count < 100)) && break
          ((page+=1))
          if ((page > 50)); then ci_error='commit statuses pagination limit exceeded'; break; fi
        done
      fi
    fi
    if [[ -n "$ci_error" ]]; then
      warn "$branch CI coverage: unavailable ($ci_error; $required_count required)"
    else
      available_count="$(jq 'length' <<<"$available_names")"
      # Display how many observed checks are selected as required; an existing
      # required rule referring to an absent check must not count as coverage.
      covered_count="$(jq -cn --argjson a "$available_names" --argjson r "$required_names" '[$a[] | select(. as $x | $r | index($x) != null)] | length')"
      if ((available_count > 0 && covered_count == available_count)); then
        ok "$branch CI checks required/available: $covered_count/$available_count"
      else
        warn "$branch CI checks required/available: $covered_count/$available_count"
      fi
      # Required contexts not present on the branch tip are not reflected in
      # the numerator, so report them explicitly rather than silently passing.
      unobserved="$(jq -cn --argjson a "$available_names" --argjson r "$required_names" '[$r[] | select(. as $x | $a | index($x) == null)] | join(", ")')"
      if [[ -n "$unobserved" ]]; then
        warn "$branch required CI contexts not observed on tip: $unobserved"
      fi
    fi
  done
  warn 'Ruleset bypass permissions and actual push/merge behavior cannot be verified by this audit'
done
unset token
printf '\nSummary: ✅ %s passed  ⚠️ %s warnings  ❌ %s failures (%s repositories)\n' "$passed" "$warnings" "$failures" "${#repos[@]}"
((failures == 0))
