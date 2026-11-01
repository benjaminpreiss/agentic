#!/usr/bin/env bash
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
STAGE="$(mktemp -d "$ROOT/.deployment-stage-test.XXXXXXXX")"
trap 'rm -rf -- "$STAGE"' EXIT
bash "$ROOT/scripts/stage-github-protection.sh" "$STAGE"
for f in check.sh github-api.sh ci.sh policy.jq rulesets.jq; do
  cmp "$ROOT/github-protection/$f" "$STAGE/github-protection/$f"
done
[[ ! -e "$STAGE/secrets" && ! -e "$STAGE/github-protection/test.sh" ]] || {
  echo 'Staged secrets or test fixtures unexpectedly' >&2; exit 1;
}
printf 'Deployment audit sources staged without credentials\n'
