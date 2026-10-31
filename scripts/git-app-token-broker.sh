# Run only by agentic-git-credentials@.service. The systemd socket is stdin/stdout.
set -euo pipefail

# stderr goes to the journal; stdout is the credential socket. Never log
# responses, JWTs, tokens, keys, or the caller-supplied repository name.
fail() { printf 'git token broker: %s\n' "$1" >&2; exit 1; }

IFS= read -r requested_repo || fail 'missing repository request'
# Never let the caller choose an API path or installation ID without validation.
[[ "$requested_repo" =~ ^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)$ ]] || fail 'invalid repository request'
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
[[ "$repo" != . && "$repo" != .. && "${GITHUB_APP_ID:-}" =~ ^[0-9]+$ ]] || fail 'invalid repository or App ID'
key="${CREDENTIALS_DIRECTORY:?}/github-app.pem"

b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
# JWT headers are a protocol constant, not a repository or App setting.
# GitHub Apps sign JWTs with RS256 (RSA/SHA-256).
header="$(printf '{"alg":"RS256","typ":"JWT"}' | b64url)"
payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$GITHUB_APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
unsigned="$header.$payload"
signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$key" | b64url)" || fail 'JWT signing failed'
jwt="$unsigned.$signature"

# Discover the installation of this single App for the requested repository.
# This also rejects repositories where the App is not installed. An App can
# have multiple installations (e.g. across different owners).
installation="$(curl --silent --show-error --max-time 30 \
  --header "Authorization: Bearer $jwt" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --write-out '\n%{http_code}' \
  "https://api.github.com/repos/$owner/$repo/installation")" || fail 'installation lookup transport failed'
[[ "${installation##*$'\n'}" == 200 ]] || fail "installation lookup HTTP ${installation##*$'\n'}"
installation_id="$(jq -er '.id | select(type == "number") | tostring' <<<"${installation%$'\n'*}" 2>/dev/null)" || fail 'installation lookup returned no numeric ID'
[[ "$installation_id" =~ ^[0-9]+$ ]] || fail 'installation lookup returned invalid ID'

# Request a token limited to this repository and Contents write. Neither
# response nor authorization headers are logged; the token stays in memory.
request_body="$(jq -cn --arg repo "$repo" '{repositories:[$repo],permissions:{contents:"write"}}')"
response="$(curl --silent --show-error --max-time 30 --request POST \
  --header "Authorization: Bearer $jwt" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --header 'Content-Type: application/json' \
  --data "$request_body" \
  --write-out '\n%{http_code}' \
  "https://api.github.com/app/installations/$installation_id/access_tokens")" || fail 'token request transport failed'
[[ "${response##*$'\n'}" == 201 ]] || fail "token request HTTP ${response##*$'\n'}"
body="${response%$'\n'*}"
# Tokens are opaque: GitHub may change their punctuation. The socket and Git
# credential protocol are line-based, so reject whitespace/control characters
# rather than guessing a token alphabet. Never log a token or response body.
token="$(jq -er '.token | select(type == "string" and test("^[!-~]+$"))' <<<"$body" 2>/dev/null)" || fail 'token response missing printable ASCII token'
printf '%s\n' "$token"
