# Run only by agentic-git-credentials@.service. The systemd socket is stdin/stdout.
set -euo pipefail

IFS= read -r requested_repo || exit 1
# Never let the caller choose an API path or installation ID without validation.
[[ "$requested_repo" =~ ^([A-Za-z0-9][A-Za-z0-9-]*)/([A-Za-z0-9._-]+)$ ]] || exit 1
owner="${BASH_REMATCH[1]}"
repo="${BASH_REMATCH[2]}"
[[ "$repo" != . && "$repo" != .. && "${GITHUB_APP_ID:-}" =~ ^[0-9]+$ ]] || exit 1
key="${CREDENTIALS_DIRECTORY:?}/github-app.pem"

b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$GITHUB_APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
unsigned="$header.$payload"
signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$key" | b64url)"
jwt="$unsigned.$signature"

# Discover the installation of this single App for the requested repository.
# This also rejects repositories where the App is not installed. An App can
# have multiple installations (e.g. across different owners).
installation="$(curl --silent --show-error --max-time 30 \
  --header "Authorization: Bearer $jwt" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --write-out '\n%{http_code}' \
  "https://api.github.com/repos/$owner/$repo/installation")"
[[ "${installation##*$'\n'}" == 200 ]] || exit 1
installation_id="$(jq -er '.id | select(type == "number") | tostring' <<<"${installation%$'\n'*}")"
[[ "$installation_id" =~ ^[0-9]+$ ]] || exit 1

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
  "https://api.github.com/app/installations/$installation_id/access_tokens")"
[[ "${response##*$'\n'}" == 201 ]] || exit 1
body="${response%$'\n'*}"
token="$(jq -er '.token | select(type == "string" and test("^[A-Za-z0-9_]+$"))' <<<"$body")"
printf '%s\n' "$token"
