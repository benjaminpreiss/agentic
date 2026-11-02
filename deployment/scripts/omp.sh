work_root="$(realpath -e "$HOME/work")"
current="$(realpath -e "$PWD")"
case "$current/" in
  "$work_root/"*) ;;
  *) echo "omp: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
esac
exec @NONO@/bin/nono run --profile omp-agentic --allow-cwd \
  --allow-unix-socket /run/agentic-git-credentials.sock \
  -- @OMP@/bin/omp "$@"
