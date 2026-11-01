#!/usr/bin/env bash
# Print a prefilled GitHub App registration URL for this project.
# No network calls or credentials; Bash 3.2 compatible.
set -euo pipefail
if [[ $# -gt 1 ]]; then
  echo 'Usage: bash scripts/github/print-app-registration-url.sh [APP-NAME]' >&2
  exit 2
fi
name="${1:-agentic-workbox}"
[[ "$name" =~ ^[A-Za-z0-9][A-Za-z0-9-]*$ ]] || {
  echo 'Use a hyphenated alphanumeric App name' >&2; exit 2;
}
# The homepage identifies this project, not the repositories an installation
# can access. Restrict the optional name to URL-safe characters.
printf 'https://github.com/settings/apps/new?name=%s&description=Sandboxed%%20coding%%20agents%%20with%%20gated%%20merges&url=https%%3A%%2F%%2Fgithub.com%%2Fbenjaminpreiss%%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=read&issues=read&actions=read&checks=read&statuses=read\n' "$name"
