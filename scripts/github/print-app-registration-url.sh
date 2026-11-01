#!/usr/bin/env bash
# Print a prefilled GitHub App registration URL for a chosen repository.
# No network calls or credentials; Bash 3.2 compatible.
set -euo pipefail
if [[ $# -ne 2 ]]; then
  echo 'Usage: bash scripts/github/print-app-registration-url.sh OWNER/REPO APP-NAME' >&2
  exit 2
fi
repo="$1"; name="$2"
[[ "$repo" == */* && "$repo" != */*/* ]] || { echo 'Expected exactly OWNER/REPO' >&2; exit 2; }
owner="${repo%%/*}"; project="${repo#*/}"
[[ "$owner" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ && "$project" =~ ^[A-Za-z0-9._-]+$ && "$name" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || {
  echo 'Use a GitHub OWNER/REPO and a hyphenated alphanumeric App name' >&2; exit 2;
}
# Restrict inputs to URL-safe characters so none can inject query parameters.
printf 'https://github.com/settings/apps/new?name=%s&description=Sandboxed%%20coding%%20agents%%20with%%20gated%%20merges&url=https%%3A%%2F%%2Fgithub.com%%2F%s%%2F%s&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=read&issues=read&actions=read&checks=read&statuses=read\n' "$name" "$owner" "$project"
