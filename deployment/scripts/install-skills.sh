install -d -o agentic -g users -m 0755 /home/agentic/.pi /home/agentic/.pi/agent /home/agentic/.pi/agent/skills
install -d -o agentic -g users -m 0755 /home/agentic/.config /home/agentic/.config/nono
install -d -o agentic -g users -m 0700 /home/agentic/.config/nono/profiles
managed=/home/agentic/.pi/agent/skills/agentic
if [ -L "$managed" ] || { [ -e "$managed" ] && [ ! -f "$managed/.agentic-managed" ]; }; then
  echo "Refusing to replace user-managed skills at $managed" >&2
  exit 1
fi
install -d -o agentic -g users -m 0755 "$managed"
touch "$managed/.agentic-managed"
chown agentic:users "$managed/.agentic-managed"
# Only links managed by previous agentic generations may be removed.
for entry in "$managed"/*; do
  [ -L "$entry" ] || continue
  case "$(readlink "$entry")" in /nix/store/*/enabled/*|/nix/store/*/available/*) rm -- "$entry" ;; esac
done
@SKILL_LINKS@
install -o agentic -g users -m 0600 @PI_PROFILE@ /home/agentic/.config/nono/profiles/pi-herdr.json
install -o agentic -g users -m 0600 @OMP_PROFILE@ /home/agentic/.config/nono/profiles/omp-agentic.json
