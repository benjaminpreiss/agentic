#!/usr/bin/env bash
# Read-only GitHub App installation branch protection audit.
# Default: inspect ruleset patterns plus representative effective branches.
# --all-branches: additionally inspect every existing branch (slower).
set -euo pipefail
umask 077

[[ $# == 0 || ($# == 1 && $1 == --all-branches) ]] || { echo 'Usage: bash github-protection/check.sh [--all-branches]' >&2; exit 2; }
all_branches=false
[[ $# == 0 ]] || all_branches=true
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SECRETS="${AGENTIC_GITHUB_SECRETS_DIR:-$ROOT/secrets/github-app}"
API=https://api.github.com
for cmd in curl jq openssl date base64; do command -v "$cmd" >/dev/null || { echo "ERROR: missing $cmd" >&2; exit 2; }; done
[[ -r "$SECRETS/app.env" ]] || { echo 'ERROR: missing secrets/github-app/app.env' >&2; exit 2; }
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

# No credentials on disk other than the pre-existing PEM; redact curl errors.
BODY=''; STATUS=''
api() {
  local method="$1" url="$2" credential="$3" result
  result="$(curl --silent --show-error --max-time 30 --request "$method" \
    --header 'Accept: application/vnd.github+json' \
    --header 'X-GitHub-Api-Version: 2022-11-28' \
    --header "Authorization: Bearer $credential" \
    --write-out $'\n%{http_code}' "$url")" || return 1
  STATUS="${result##*$'\n'}"; BODY="${result%$'\n'*}"
  [[ "$STATUS" =~ ^[0-9][0-9][0-9]$ ]]
}
api POST "$API/app/installations/$INSTALL_ID/access_tokens" "$jwt" || { echo 'ERROR: token request failed' >&2; exit 2; }
[[ "$STATUS" == 201 ]] || { echo "ERROR: installation token request HTTP $STATUS" >&2; exit 2; }
token="$(jq -er '.token | select(type=="string" and length>0)' <<<"$BODY")" || { echo 'ERROR: installation token missing' >&2; exit 2; }
unset jwt unsigned signature

repos=()
page=1
while :; do
  api GET "$API/installation/repositories?per_page=100&page=$page" "$token" || { echo 'ERROR: repository listing failed' >&2; exit 2; }
  [[ "$STATUS" == 200 ]] || { echo "ERROR: listing repositories HTTP $STATUS" >&2; exit 2; }
  count="$(jq -er '.repositories | arrays | length' <<<"$BODY")" || { echo 'ERROR: unexpected repositories response' >&2; exit 2; }
  while IFS= read -r repo; do [[ -z "$repo" ]] || repos+=("$repo"); done < <(jq -r '.repositories[].full_name' <<<"$BODY")
  ((count < 100)) && break
  ((page+=1)); ((page < 1000)) || { echo 'ERROR: too many repository pages' >&2; exit 2; }
done
printf 'GitHub App installation %s: %s repositories\nRead-only %s audit; no GitHub settings are changed.\n' "$INSTALL_ID" "${#repos[@]}" "$(if $all_branches; then echo full-branch; else echo ruleset-focused; fi)"
failures=0; warnings=0; passed=0
ok()   { printf '  ✅ %s\n' "$1"; ((passed+=1)); }
warn() { printf '  ⚠️  %s\n' "$1"; ((warnings+=1)); }
fail() { printf '  ❌ %s\n' "$1"; ((failures+=1)); }

report() {
  local branch="$1" results="$2" status message
  if ! jq -e 'type == "array" and length > 0 and all(.[]; (.status == "ok" or .status == "warn" or .status == "fail") and (.message | type == "string"))' >/dev/null <<<"$results"; then
    fail "$branch: policy evaluator returned invalid results"; return 1
  fi
  while IFS=$'\t' read -r status message; do
    case "$status" in
      ok) ok "$branch: $message" ;;
      warn) warn "$branch: $message" ;;
      fail) fail "$branch: $message" ;;
    esac
  done < <(jq -r '.[] | [.status, .message] | @tsv' <<<"$results")
}

check_effective() {
  local branch="$1" encoded results
  encoded="$(jq -rn --arg v "$branch" '$v|@uri')"
  if ! api GET "$API/repos/$repo/rules/branches/$encoded?per_page=100" "$token"; then
    fail "$branch: effective rules API transport error"; return 1
  elif [[ "$STATUS" != 200 ]]; then
    fail "$branch: effective rules HTTP $STATUS"; return 1
  elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
    fail "$branch: invalid effective rules response"; return 1
  fi
  if ! results="$(jq -c --arg branch "$branch" -f "$ROOT/github-protection/policy.jq" <<<"$BODY")"; then
    fail "$branch: policy evaluation failed"; return 1
  fi
  report "$branch" "$results"
}

# Check CI only at main's tip. Tip contexts are a snapshot, not a complete PR CI inventory.
check_main_ci() {
  local sha="$1" required available names count page error='' covered unobserved
  required="$(jq -c '[.[] | select(.type=="required_status_checks") | .parameters.required_status_checks[]? | (.context // empty)] | unique' <<<"$BODY")"
  available='[]'
  if [[ ! "$sha" =~ ^[0-9a-fA-F]{40}$ ]]; then error='main tip SHA unavailable'; fi
  if [[ -z "$error" ]]; then
    for kind in check-runs statuses; do
      page=1
      while :; do
        if ! api GET "$API/repos/$repo/commits/$sha/$kind?per_page=100&page=$page" "$token"; then
          error="$kind request failed"; break
        elif [[ "$STATUS" != 200 ]]; then
          error="$kind HTTP $STATUS"; break
        fi
        if [[ "$kind" == check-runs ]]; then
          if ! jq -e '.check_runs | type=="array"' >/dev/null <<<"$BODY"; then error='invalid check-runs response'; break; fi
          names="$(jq -c '[.check_runs[].name | select(type=="string")] | unique' <<<"$BODY")"
          count="$(jq '.check_runs | length' <<<"$BODY")"
        else
          if ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then error='invalid statuses response'; break; fi
          names="$(jq -c '[.[].context | select(type=="string")] | unique' <<<"$BODY")"
          count="$(jq 'length' <<<"$BODY")"
        fi
        available="$(jq -cn --argjson a "$available" --argjson b "$names" '$a + $b | unique')"
        ((count < 100)) && break
        ((page+=1)); if ((page > 50)); then error="$kind pagination limit exceeded"; break; fi
      done
      [[ -z "$error" ]] || break
    done
  fi
  if [[ -n "$error" ]]; then warn "main CI coverage unavailable ($error)"; return; fi
  covered="$(jq -cn --argjson a "$available" --argjson r "$required" '[$a[] | select(. as $x | $r | index($x) != null)] | length')"
  count="$(jq 'length' <<<"$available")"
  if ((count > 0 && covered == count)); then ok "main CI checks required/available: $covered/$count"; else warn "main CI checks required/available: $covered/$count"; fi
  unobserved="$(jq -cn --argjson a "$available" --argjson r "$required" '[$r[] | select(. as $x | $a | index($x) == null)] | join(", ")')"
  [[ -z "$unobserved" ]] || warn "main required CI contexts not observed on tip: $unobserved"
}

for repo in "${repos[@]}"; do
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo 'ERROR: invalid repository identifier' >&2; exit 2; }
  printf '\n📦 %s\n' "$repo"
  # List applicable repository + parent rulesets, then fetch each full ruleset.
  # The list may omit rule parameters and bypass actors; never infer them from it.
  sets='[]'; page=1; list_ok=true
  while :; do
    if ! api GET "$API/repos/$repo/rulesets?includes_parents=true&per_page=100&page=$page" "$token"; then
      fail 'ruleset listing: API transport error'; list_ok=false; break
    elif [[ "$STATUS" != 200 ]]; then
      fail "ruleset listing: HTTP $STATUS"; list_ok=false; break
    elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
      fail 'ruleset listing: invalid response'; list_ok=false; break
    fi
    sets="$(jq -cn --argjson a "$sets" --argjson b "$BODY" '$a + $b')"
    count="$(jq 'length' <<<"$BODY")"
    ((count < 100)) && break
    ((page+=1)); if ((page > 50)); then fail 'ruleset pagination limit exceeded'; list_ok=false; break; fi
  done
  if [[ "$list_ok" == true ]]; then
    details='[]'; details_ok=true
    while IFS= read -r id; do
      if ! api GET "$API/repos/$repo/rulesets/$id?includes_parents=true" "$token"; then
        fail "ruleset $id: API transport error"; details_ok=false; break
      elif [[ "$STATUS" != 200 ]]; then
        fail "ruleset $id: HTTP $STATUS"; details_ok=false; break
      elif ! jq -e 'type=="object" and (.rules|type)=="array"' >/dev/null <<<"$BODY"; then
        fail "ruleset $id: missing rule details"; details_ok=false; break
      fi
      details="$(jq -cn --argjson a "$details" --argjson b "$BODY" '$a + [$b]')"
    done < <(jq -r '.[].id | select(type=="number")' <<<"$sets")
    if [[ "$details_ok" == true ]] && [[ "$(jq 'length' <<<"$sets")" != "$(jq 'length' <<<"$details")" ]]; then
      fail 'ruleset listing contained IDs that could not be inspected'; details_ok=false
    fi
    if [[ "$details_ok" == true ]]; then
      if results="$(jq -c --argjson app_id "$APP_ID" -f "$ROOT/github-protection/rulesets.jq" <<<"$details")"; then
        report 'rulesets' "$results" || true
      else fail 'ruleset policy evaluation failed'; fi
    fi
  fi

  # main must exist. In the normal mode only sample at most one existing
  # branch from each additional class, without enumerating all branches.
  if ! api GET "$API/repos/$repo/branches/main" "$token"; then
    fail 'main: branch API transport error'
  elif [[ "$STATUS" != 200 ]]; then
    fail "main: branch HTTP $STATUS"
  else
    main_sha="$(jq -r '.commit.sha // empty' <<<"$BODY")"
    if check_effective main; then check_main_ci "$main_sha"; fi
  fi

  branches=(); page=1; listing_ok=true
  while :; do
    if ! api GET "$API/repos/$repo/branches?per_page=100&page=$page" "$token"; then
      fail 'branch sample listing: API transport error'; listing_ok=false; break
    elif [[ "$STATUS" != 200 ]] || ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
      fail "branch sample listing: HTTP $STATUS or invalid response"; listing_ok=false; break
    fi
    while IFS= read -r branch; do branches+=("$branch"); done < <(jq -r '.[].name' <<<"$BODY")
    count="$(jq 'length' <<<"$BODY")"
    ((count < 100)) && break
    if [[ "$all_branches" == false ]]; then
      warn 'only first 100 branch names sampled; ruleset pattern check covers future names conservatively'; break
    fi
    ((page+=1)); if ((page > 50)); then fail 'branch listing pagination limit exceeded'; listing_ok=false; break; fi
  done
  if [[ "$listing_ok" == true ]]; then
    if [[ "$all_branches" == true ]]; then
      for branch in "${branches[@]}"; do [[ "$branch" == main ]] || check_effective "$branch" || true; done
    else
      agentic_sample=''; other_sample=''
      for branch in "${branches[@]}"; do
        case "$branch" in
          agentic/*) [[ -n "$agentic_sample" ]] || agentic_sample="$branch" ;;
          main) ;;
          *) [[ -n "$other_sample" ]] || other_sample="$branch" ;;
        esac
      done
      if [[ -n "$agentic_sample" ]]; then check_effective "$agentic_sample" || true; else warn 'no existing agentic/* branch sampled'; fi
      if [[ -n "$other_sample" ]]; then check_effective "$other_sample" || true; else warn 'no other non-agentic/* branch sampled'; fi
    fi
  fi
  warn 'Effective rules do not prove reviewer identity or actual merge authorization; test with App credentials and use a trusted merge gate'
done
unset token
printf '\nSummary: ✅ %s passed  ⚠️ %s warnings  ❌ %s failures (%s repositories)\n' "$passed" "$warnings" "$failures" "${#repos[@]}"
((failures == 0))
