# Called as agentic by agentic-configure-git-credentials.service.
set -euo pipefail
helper="${1:?missing Git credential helper}"
socket="${2:?missing token broker socket}"
# Apply to all github.com HTTPS repositories, not to one checkout or owner.
key=credential.https://github.com.helper
expected_helper="$helper $socket"

# Git config writes replace ~/.gitconfig. Avoid even a no-op write: running
# nono sessions may hold an inode-bound read grant for the existing file.
mapfile -t helpers < <(git config --global --get-all "$key" || true)
if (( ${#helpers[@]} != 2 )) || [[ ${helpers[0]} != "" || ${helpers[1]} != "$expected_helper" ]]; then
  git config --global --unset-all "$key" || true
  # An empty helper resets inherited helpers for this URL.
  git config --global --add "$key" ""
  git config --global --add "$key" "$expected_helper"
fi
if [[ "$(git config --global --get credential.https://github.com.useHttpPath || true)" != true ]]; then
  git config --global credential.https://github.com.useHttpPath true
fi

# Author attribution is separate from GitHub App authentication. Only fill
# missing/empty agentic-global fields; never override an explicit identity.
if [[ -z "$(git config --global --get user.name || true)" ]]; then
  git config --global user.name 'agentic-workbox[bot]'
fi
if [[ -z "$(git config --global --get user.email || true)" ]]; then
  git config --global user.email 'agentic@localhost'
fi
