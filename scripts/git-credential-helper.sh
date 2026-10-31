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

token="$(printf '%s\n' "$path" | socat - "UNIX-CONNECT:$socket")" || exit 1
[[ "$token" =~ ^[A-Za-z0-9_]+$ ]] || exit 1
printf 'username=x-access-token\npassword=%s\n\n' "$token"
