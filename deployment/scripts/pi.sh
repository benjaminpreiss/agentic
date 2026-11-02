export HERDR_AGENT=pi
export JITI_FS_CACHE=false
work_root="$(realpath -e "$HOME/work")"
current="$(realpath -e "$PWD")"
case "$current/" in
  "$work_root/"*) ;;
  *) echo "pi: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
esac
exec @NONO@/bin/nono run --profile pi-herdr --allow-cwd \
  --allow-unix-socket /run/agentic-github-mcp.sock \
  --allow-unix-socket /run/agentic-git-credentials.sock \
  -- @PI@/bin/pi "$@"
