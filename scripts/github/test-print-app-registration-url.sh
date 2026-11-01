#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/print-app-registration-url.sh"
url="$(bash "$script")"
[[ "$url" == 'https://github.com/settings/apps/new?name=agentic-workbox&'* ]]
[[ "$url" == *'url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&'* ]]
[[ "$url" == *'&contents=write&pull_requests=read&issues=read&'* ]]
[[ "$(bash "$script" custom-agent)" == *'name=custom-agent&'* ]]
if bash "$script" 'app&contents=admin' >/dev/null 2>&1; then
  echo 'Accepted query injection in App name' >&2; exit 1
fi
if bash "$script" first second >/dev/null 2>&1; then
  echo 'Accepted extra arguments' >&2; exit 1
fi
echo 'GitHub App registration URL: PASS'
