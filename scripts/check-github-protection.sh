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
for repo in "${repos[@]}"; do
  [[ "$repo" =~ ^[A-Za-z0-9_.-]+/[A-Za-z0-9_.-]+$ ]] || { echo "ERROR: invalid repository identifier" >&2; exit 2; }
  echo "$repo"
  for branch in main agentic; do
    api GET "$API/repos/$repo/branches/$branch" "$token" || { echo "  $branch: UNKNOWN (transport error)"; ((failures+=1)); continue; }
    if [[ "$STATUS" == 404 ]]; then echo "  $branch: NOT FOUND"; ((failures+=1)); continue; fi
    if [[ "$STATUS" != 200 ]]; then echo "  $branch: UNKNOWN (branch HTTP $STATUS)"; ((failures+=1)); continue; fi
    api GET "$API/repos/$repo/rules/branches/$branch?per_page=100" "$token" || { echo "  $branch: UNKNOWN (rules transport error)"; ((failures+=1)); continue; }
    if [[ "$STATUS" != 200 ]]; then echo "  $branch: UNKNOWN (rules HTTP $STATUS)"; ((failures+=1)); continue; fi
    if ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then echo "  $branch: UNKNOWN (invalid rules)"; ((failures+=1)); continue; fi
    issues=()
    for spec in 'pull_request:require a pull request' 'required_status_checks:require CI checks' 'non_fast_forward:block force pushes' 'deletion:block deletion'; do
      typ="${spec%%:*}"; label="${spec#*:}"
      jq -e --arg t "$typ" 'any(.[]; .type==$t)' >/dev/null <<<"$BODY" || issues+=("MISSING: $label")
    done
    if [[ "$branch" == main ]]; then
      jq -e '[.[]|select(.type=="pull_request")|(.parameters.required_approving_review_count // 0)]|any(.>=1)' >/dev/null <<<"$BODY" || issues+=('MISSING: at least one required PR approval')
    else
      jq -e '[.[]|select(.type=="pull_request")|(.parameters.required_approving_review_count // 0)]|any(.>0)' >/dev/null <<<"$BODY" && issues+=('REVIEW: approval required on agentic may prevent autonomous merges')
    fi
    jq -e '[.[]|select(.type=="required_status_checks")|(.parameters.required_status_checks // [])]|any(length>0)' >/dev/null <<<"$BODY" || issues+=('MISSING: selected required CI checks')
    if ((${#issues[@]})); then
      echo "  $branch: NEEDS ATTENTION"
      printf '    - %s\n' "${issues[@]}"
      ((failures+=1))
    else
      echo "  $branch: rule checks present (bypass actors NOT verified)"
    fi
  done
  echo
done
unset token
printf 'NOT VERIFIED: ruleset bypass actors, reviewer identity, or real push/merge behavior.\n'
printf 'Finished: %s repository(s), %s branch(es) needing attention.\n' "${#repos[@]}" "$failures"
((failures == 0))
