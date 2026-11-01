#!/usr/bin/env bash
# Sourced by check.sh. Owns App authentication and paginated GitHub reads.
# Interface: authenticate, list_repos, load_rulesets(repo), load_branches(repo, full).
# Sets token, APP_ID, INSTALL_ID, repos, details, branches; api sets BODY/STATUS.
# load_* reports errors through the caller's fail/warn functions and returns 1
# when its result is incomplete. Never print credentials or response bodies.
API=https://api.github.com
BODY=''; STATUS=''

read_setting() {
  local value
  value="$(sed -n "s/^[[:space:]]*$1[[:space:]]*=[[:space:]]*//p" "$SECRETS/app.env" | tail -n 1 | tr -d '\r')"
  value="${value%\"}"; value="${value#\"}"
  printf '%s' "$value"
}
b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }

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

authenticate() {
  local key real_key real_dir now header payload unsigned signature jwt
  [[ -r "$SECRETS/app.env" ]] || { echo 'ERROR: missing secrets/github-app/app.env' >&2; return 2; }
  APP_ID="$(read_setting GITHUB_APP_ID)"
  INSTALL_ID="$(read_setting GITHUB_APP_INSTALLATION_ID)"
  [[ "$APP_ID" =~ ^[0-9]+$ && "$INSTALL_ID" =~ ^[0-9]+$ ]] || { echo 'ERROR: expected numeric App and installation IDs' >&2; return 2; }
  key="$SECRETS/private-key.pem"
  [[ -f "$key" && -r "$key" ]] || { echo 'ERROR: missing active private-key.pem' >&2; return 2; }
  real_key="$(cd -P "$(dirname "$key")" && realpath "$key")"
  real_dir="$(cd -P "$SECRETS" && pwd)"
  case "$real_key" in "$real_dir"/*) ;; *) echo 'ERROR: active key must resolve inside secrets directory' >&2; return 2;; esac
  now="$(date +%s)"
  # Encode the JWT header from its declared algorithm/type, not an opaque blob.
  header="$(printf '%s' '{"alg":"RS256","typ":"JWT"}' | b64url)"
  payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
  unsigned="$header.$payload"
  signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$real_key" | b64url)" || { echo 'ERROR: could not sign JWT' >&2; return 2; }
  jwt="$unsigned.$signature"
  api POST "$API/app/installations/$INSTALL_ID/access_tokens" "$jwt" || { echo 'ERROR: token request failed' >&2; return 2; }
  [[ "$STATUS" == 201 ]] || { echo "ERROR: installation token request HTTP $STATUS" >&2; return 2; }
  token="$(jq -er '.token | select(type=="string" and length>0)' <<<"$BODY")" || { echo 'ERROR: installation token missing' >&2; return 2; }
}

list_repos() {
  local page=1 count repo
  repos=()
  while :; do
    api GET "$API/installation/repositories?per_page=100&page=$page" "$token" || { echo 'ERROR: repository listing failed' >&2; return 2; }
    [[ "$STATUS" == 200 ]] || { echo "ERROR: listing repositories HTTP $STATUS" >&2; return 2; }
    count="$(jq -er '.repositories | arrays | length' <<<"$BODY")" || { echo 'ERROR: unexpected repositories response' >&2; return 2; }
    while IFS= read -r repo; do [[ -z "$repo" ]] || repos+=("$repo"); done < <(jq -r '.repositories[].full_name' <<<"$BODY")
    ((count < 100)) && break
    ((page+=1)); ((page < 1000)) || { echo 'ERROR: too many repository pages' >&2; return 2; }
  done
}

load_rulesets() {
  local repo="$1" sets='[]' page=1 count id
  details='[]'
  while :; do
    if ! api GET "$API/repos/$repo/rulesets?includes_parents=true&per_page=100&page=$page" "$token"; then
      fail 'ruleset listing: API transport error'; return 1
    elif [[ "$STATUS" != 200 ]]; then
      fail "ruleset listing: HTTP $STATUS"; return 1
    elif ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
      fail 'ruleset listing: invalid response'; return 1
    fi
    sets="$(jq -cn --argjson a "$sets" --argjson b "$BODY" '$a + $b')"
    count="$(jq 'length' <<<"$BODY")"
    ((count < 100)) && break
    ((page+=1)); if ((page > 50)); then fail 'ruleset pagination limit exceeded'; return 1; fi
  done
  while IFS= read -r id; do
    if ! api GET "$API/repos/$repo/rulesets/$id?includes_parents=true" "$token"; then
      fail "ruleset $id: API transport error"; return 1
    elif [[ "$STATUS" != 200 ]]; then
      fail "ruleset $id: HTTP $STATUS"; return 1
    elif ! jq -e 'type=="object" and (.rules|type)=="array"' >/dev/null <<<"$BODY"; then
      fail "ruleset $id: missing rule details"; return 1
    fi
    details="$(jq -cn --argjson a "$details" --argjson b "$BODY" '$a + [$b]')"
  done < <(jq -r '.[].id | select(type=="number")' <<<"$sets")
  if [[ "$(jq 'length' <<<"$sets")" != "$(jq 'length' <<<"$details")" ]]; then
    fail 'ruleset listing contained IDs that could not be inspected'; return 1
  fi
}

load_branches() {
  local repo="$1" full="$2" page=1 count branch
  branches=()
  while :; do
    if ! api GET "$API/repos/$repo/branches?per_page=100&page=$page" "$token"; then
      fail 'branch sample listing: API transport error'; return 1
    elif [[ "$STATUS" != 200 ]] || ! jq -e 'type=="array"' >/dev/null <<<"$BODY"; then
      fail "branch sample listing: HTTP $STATUS or invalid response"; return 1
    fi
    while IFS= read -r branch; do branches+=("$branch"); done < <(jq -r '.[].name' <<<"$BODY")
    count="$(jq 'length' <<<"$BODY")"
    ((count < 100)) && break
    if [[ "$full" == false ]]; then
      warn 'only first 100 branch names sampled; ruleset pattern check covers future names conservatively'; break
    fi
    ((page+=1)); if ((page > 50)); then fail 'branch listing pagination limit exceeded'; return 1; fi
  done
}
