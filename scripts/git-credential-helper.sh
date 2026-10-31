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
# Fail closed for other repositories, protocols, or hosts.
[[ "$protocol" == https && "$host" == github.com && "$path" == benjaminpreiss/agentic.git ]] || exit 0

token="$(printf 'token\n' | socat - "UNIX-CONNECT:$socket")" || exit 1
[[ "$token" =~ ^[A-Za-z0-9_]+$ ]] || exit 1
printf 'username=x-access-token\npassword=%s\n\n' "$token"
