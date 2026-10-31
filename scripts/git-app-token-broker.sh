# Run only by agentic-git-credentials@.service. The systemd socket is stdin/stdout.
set -euo pipefail

IFS= read -r request || exit 1
[[ "$request" == token ]] || exit 1
[[ "${GITHUB_APP_ID:-}" =~ ^[0-9]+$ && "${GITHUB_APP_INSTALLATION_ID:-}" =~ ^[0-9]+$ ]] || exit 1
key="${CREDENTIALS_DIRECTORY:?}/github-app.pem"

b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }
now="$(date +%s)"
header='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$GITHUB_APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
unsigned="$header.$payload"
signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$key" | b64url)"
jwt="$unsigned.$signature"

# Neither curl output nor its request headers are logged. A non-201
# response yields no credential; tokens are never written to disk.
response="$(curl --silent --show-error --max-time 30 --request POST \
  --header "Authorization: Bearer $jwt" \
  --header 'Accept: application/vnd.github+json' \
  --header 'X-GitHub-Api-Version: 2022-11-28' \
  --header 'Content-Type: application/json' \
  --data '{"repositories":["agentic"],"permissions":{"contents":"write"}}' \
  --write-out '\n%{http_code}' \
  "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens")"
[[ "${response##*$'\n'}" == 201 ]] || exit 1
body="${response%$'\n'*}"
token="$(jq -er '.token | select(type == "string" and test("^[A-Za-z0-9_]+$"))' <<<"$body")"
printf '%s\n' "$token"
