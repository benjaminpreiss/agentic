umask 077
store=/var/backups/agentic
mkdir -p "$store"
test -d /home/agentic || exit 1
stamp="$(date -u +%Y%m%dT%H%M%SZ)"
tmp="$store/agentic-$stamp-$$.tar.gz.partial"
dest="${tmp%.partial}"
trap 'rm -f "$tmp"' EXIT
tar -C /home -czpf "$tmp" --one-file-system agentic
gzip -t "$tmp"
mv "$tmp" "$dest"
find "$store" -maxdepth 1 -name 'agentic-*.tar.gz' -type f -printf '%f\n' | sort -r | tail -n +15 | while IFS= read -r old; do rm -f -- "$store/$old"; done
echo "Backup completed: $dest"
