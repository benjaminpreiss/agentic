#!/usr/bin/env bash
# Run outside an existing nono session on a host with the Pi pack installed.
set -euo pipefail

repo="$(cd "$(dirname "$0")/.." && pwd)"
profile="$repo/profiles/pi-herdr.json"
root="$(mktemp -d "$HOME/work/.pi-sandbox-test.XXXXXXXX")"
trap 'rm -rf -- "$root"' EXIT
mkdir -p "$root/project" "$root/sibling" "$root/state"
printf 'private\n' > "$root/sibling/secret"
printf 'project\n' > "$root/project/readme"

cd "$root/project"
for attempt in 1 2; do
  # Keep nono's supervisor state outside the granted project directory.
  output="$(XDG_STATE_HOME="$root/state" nono run --profile "$profile" --allow-cwd -- bash -c '
    head -c 1 readme >/dev/null || exit 1
    if head -c 1 "$1" >/dev/null 2>&1; then echo "sibling was readable"; exit 1; fi
    if ls /tmp >/dev/null 2>&1; then echo "/tmp was readable"; exit 1; fi
    echo "cwd allowed; sibling and /tmp denied"
  ' _ "$root/sibling/secret" 2>&1)"
  grep -Fq 'cwd allowed; sibling and /tmp denied' <<< "$output" || { printf '%s\n' "$output"; exit 1; }
  if grep -Fq 'Review denied paths' <<< "$output"; then
    printf 'Unexpected grant UI on attempt %s:\n%s\n' "$attempt" "$output" >&2
    exit 1
  fi
done
printf 'Pi sandbox: CWD allowed, sibling and /tmp denied on both launches.\n'
