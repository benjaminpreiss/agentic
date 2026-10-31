# Called as agentic by agentic-configure-git-credentials.service.
set -euo pipefail
helper="${1:?missing Git credential helper}"
socket="${2:?missing token broker socket}"
# Apply to all github.com HTTPS repositories, not to one checkout or owner.
key=credential.https://github.com.helper

git config --global --unset-all "$key" || true
# An empty helper resets inherited helpers for this URL.
git config --global --add "$key" ""
git config --global --add "$key" "$helper $socket"
git config --global credential.https://github.com.useHttpPath true
