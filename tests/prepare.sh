#!/usr/bin/env bash
# Consumer-specific preparation fixture: no SSH server, disk or Nix build.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd -P)"
tmp=$(mktemp -d "$ROOT/.deployment.fixture.prepare.XXXXXXXX")
trap 'rm -rf "$tmp"' EXIT
mkdir -p "$tmp/repo/scripts/deployment" "$tmp/bin"
cp "$ROOT/scripts/deployment/prepare.sh" "$tmp/repo/scripts/deployment/prepare.sh"
TEST_MOSS_SOURCE=$(nix --extra-experimental-features 'nix-command flakes' eval --raw --no-write-lock-file "path:$ROOT#mossSource")
export TEST_MOSS_SOURCE
printf '#!/usr/bin/env bash\nset -eu\n[[ $* == *mossSource* ]]\nprintf "%%s\\n" "$TEST_MOSS_SOURCE"\n' > "$tmp/bin/nix"
chmod +x "$tmp/bin/nix"
cat > "$tmp/bin/ssh" <<'MOCK'
#!/usr/bin/env bash
case "$*" in
  *'uname -m;'*) printf 'x86_64\nbios\n[{"dev":"eth0"}]\n' ;;
  *'cat /sys/class/net/eth0/address'*) printf '02:00:00:00:00:01\n' ;;
  *'lsblk -dn -o TYPE'*) printf 'disk\n' ;;
  *) echo "Unexpected SSH probe: $*" >&2; exit 1 ;;
esac
MOCK
chmod +x "$tmp/bin/ssh"
printf 'ssh-ed25519 AAAAfixture test\n' > "$tmp/key.pub"
git -C "$tmp/repo" init -q
printf '/.moss/\n/.deployment/\n' > "$tmp/repo/.gitignore"
git -C "$tmp/repo" add .gitignore
git -C "$tmp/repo" -c user.name=Fixture -c user.email=fixture@example.invalid commit -q -m fixture
PATH="$tmp/bin:$PATH" bash "$tmp/repo/scripts/deployment/prepare.sh" root@fixture /dev/vda fixture "$tmp/key.pub" dhcp
[[ $(stat -c %a "$tmp/repo/.deployment/generated/machine.nix") == 600 ]]
[[ $(stat -c %a "$tmp/repo/.moss/root@fixture/machine.json") == 600 ]]
jq -e --arg repo "$tmp/repo" '.repo == $repo and .output == "agentic" and .disk == "/dev/vda" and .machine == ($repo + "/.deployment/generated") and .preEraseCheck == ($repo + "/scripts/deployment/pre-erase.sh") and .remoteState == "/var/lib/agentic/deployment"' "$tmp/repo/.moss/root@fixture/machine.json" >/dev/null
grep -Fq 'networkMAC = "02:00:00:00:00:01"' "$tmp/repo/.deployment/generated/machine.nix"
# Preparing a second machine must never overwrite the original private facts.
if PATH="$tmp/bin:$PATH" bash "$tmp/repo/scripts/deployment/prepare.sh" root@fixture /dev/vda other "$tmp/key.pub" dhcp >/dev/null 2>&1; then
  echo 'Overwrote existing machine state' >&2; exit 1
fi
echo 'Synthetic machine preparation and private moss configuration passed.'
