#!/usr/bin/env bash
# Credential-free regression test. Never contacts GitHub or invokes the helper.
set -euo pipefail
script_dir="$(cd "$(dirname "$0")" && pwd)"
script="$script_dir/configure-git-credentials.sh"
# Keep the test home inside the checkout so sandboxed runs can read and write it.
tmp="$(mktemp -d "$script_dir/../.test-git-config.XXXXXXXX")"
trap 'rm -rf "$tmp"' EXIT
export HOME="$tmp/home" GIT_CONFIG_NOSYSTEM=1
unset GIT_CONFIG_GLOBAL GIT_CONFIG_SYSTEM GIT_CONFIG_COUNT GIT_AUTHOR_NAME GIT_AUTHOR_EMAIL GIT_COMMITTER_NAME GIT_COMMITTER_EMAIL
mkdir -p "$HOME"
key=credential.https://github.com.helper
helper=/test/credential-helper
socket=/test/credential.sock

bash "$script" "$helper" "$socket"
[[ "$(git config --global --get user.name)" == 'agentic-workbox[bot]' ]]
[[ "$(git config --global --get user.email)" == '350248949+agentic-workbox[bot]@users.noreply.github.com' ]]
[[ "$(git config --global --get credential.https://github.com.useHttpPath)" == true ]]
mapfile -t helpers < <(git config --global --get-all "$key")
[[ ${#helpers[@]} == 2 && ${helpers[0]} == "" && ${helpers[1]} == "$helper $socket" ]]
# A freshly provisioned user can commit without -c user.* overrides.
git -C "$tmp" init -q repo
git -C "$tmp/repo" -c commit.gpgsign=false commit -q --allow-empty -m test
[[ "$(git -C "$tmp/repo" log -1 --format=%an)" == 'agentic-workbox[bot]' ]]

# A repeat apply must not replace the global config (or write to its inode).
before_inode="$(stat -c %i "$HOME/.gitconfig")"
before_content="$(sha256sum "$HOME/.gitconfig")"
chmod 0444 "$HOME/.gitconfig"
bash "$script" "$helper" "$socket"
[[ "$(stat -c %i "$HOME/.gitconfig")" == "$before_inode" ]]
[[ "$(sha256sum "$HOME/.gitconfig")" == "$before_content" ]]
chmod 0600 "$HOME/.gitconfig"

# Existing explicit identity is preserved even when a helper must change.
git config --global user.name 'Custom Agent'
git config --global user.email 'custom@example.invalid'
bash "$script" /test/new-helper "$socket"
[[ "$(git config --global --get user.name)" == 'Custom Agent' ]]
[[ "$(git config --global --get user.email)" == 'custom@example.invalid' ]]
mapfile -t helpers < <(git config --global --get-all "$key")
[[ ${#helpers[@]} == 2 && ${helpers[0]} == "" && ${helpers[1]} == "/test/new-helper $socket" ]]

# Preserve an explicitly set name while filling in only a missing email.
git config --global --unset user.email
bash "$script" /test/new-helper "$socket"
[[ "$(git config --global --get user.name)" == 'Custom Agent' ]]
[[ "$(git config --global --get user.email)" == '350248949+agentic-workbox[bot]@users.noreply.github.com' ]]
echo 'Git identity and helper provisioning: PASS'
