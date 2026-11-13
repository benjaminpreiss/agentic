#!/bin/sh
set -eu
grep -Eq '^ID="?opensuse-tumbleweed"?$' /etc/os-release || { echo 'Not Tumbleweed' >&2; exit 1; }
account_name=$1
shell_path=$2
case "$account_name" in
  ''|root|*[!a-z0-9-]*|[!a-z]*) echo 'Invalid unprivileged account name' >&2; exit 1 ;;
esac
test -f "$shell_path" && test -x "$shell_path" && grep -Fqx -- "$shell_path" /etc/shells || {
  echo 'Requested shell is not a registered executable' >&2; exit 1;
}
if existing=$(getent passwd "$account_name"); then
  current_shell=$(printf '%s\n' "$existing" | cut -d: -f7)
  [ "$current_shell" = "$shell_path" ] || { echo 'Existing shell differs; migration required' >&2; exit 1; }
else
  useradd -m -s "$shell_path" "$account_name"
fi
awk -F: -v name="$account_name" '$1 == name { found=1 } END { exit !found }' /etc/passwd || {
  echo 'Account is not local' >&2; exit 1;
}
result=$(getent passwd "$account_name")
uid=$(printf '%s\n' "$result" | cut -d: -f3)
configured_shell=$(printf '%s\n' "$result" | cut -d: -f7)
[ "$uid" != 0 ] && [ "$configured_shell" = "$shell_path" ] || { echo 'Account postcondition failed' >&2; exit 1; }
for group in $(id -nG "$account_name"); do
  case "$group" in wheel|sudo) echo 'Account has an administrator group' >&2; exit 1 ;; esac
done
