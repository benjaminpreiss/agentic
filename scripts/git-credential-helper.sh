# Git passes the broker's socket path first, then the credential action.
set -euo pipefail
[[ "${2:-}" == get ]] || exit 0
socket="${1:?missing token broker socket}"

protocol='' host='' path=''
while IFS= read -r line && [[ -n "$line" ]]; do
  case "$line" in
    protocol=*) protocol="${line#protocol=}" ;;
    host=*) host="${line#host=}" ;;
    path=*) path="${line#path=}" ;;
  esac
done
# Only GitHub HTTPS repository URLs are eligible. The broker independently
# validates the repository and checks that this App is installed on it.
[[ "$protocol" == https && "$host" == github.com ]] || exit 0
path="${path%.git}"
[[ "$path" =~ ^[A-Za-z0-9][A-Za-z0-9-]*/[A-Za-z0-9._-]+$ ]] || exit 0

# stdin closes immediately after the repository line. socat's default 0.5s
# EOF grace period can close the socket before the broker completes two API
# requests; allow slightly longer than their combined 60s curl timeouts.
token="$(printf '%s\n' "$path" | socat -t 75 - "UNIX-CONNECT:$socket")" || exit 1
# The broker checks for nonempty printable ASCII. Tokens are opaque, and GitHub
# may include punctuation; only exclude characters unsafe for line-based Git
# credential output, rather than relying on a guessed token alphabet.
[[ "$token" =~ ^[[:graph:]]+$ ]] || exit 1
printf 'username=x-access-token\npassword=%s\n\n' "$token"
