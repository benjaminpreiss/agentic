#!/usr/bin/env bash
set -euo pipefail
script="$(cd "$(dirname "$0")" && pwd)/print-app-registration-url.sh"
url="$(bash "$script" example-org/example-repo example-agent-app)"
[[ "$url" == 'https://github.com/settings/apps/new?name=example-agent-app&'* ]]
[[ "$url" == *'url=https%3A%2F%2Fgithub.com%2Fexample-org%2Fexample-repo&public=false&'* ]]
[[ "$url" == *'&contents=write&pull_requests=read&issues=read&'* ]]
for bad in 'example-org/example-repo?admin=true' 'example-org/example-repo/extra' '/repo'; do
  if bash "$script" "$bad" app >/dev/null 2>&1; then echo "Accepted invalid repo: $bad" >&2; exit 1; fi
done
if bash "$script" example-org/example-repo 'app&contents=admin' >/dev/null 2>&1; then
  echo 'Accepted query injection in App name' >&2; exit 1
fi
echo 'GitHub App registration URL: PASS'
