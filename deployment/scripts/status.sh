echo 'AGENTIC WORKSPACE'
echo '  Workspace: ~/work'
echo '  Switch:    cd ~/work'
echo '  Start Pi:  pi'
echo '  Start OMP: omp'
echo
echo 'AVAILABLE TOOLS'
for tool in pi omp nono herdr git node npm; do
  if command -v "$tool" >/dev/null 2>&1; then
    printf '  %-10s %s\n' "$tool" "$(command -v "$tool")"
  fi
done
echo
echo 'MAINTENANCE'
@SYSTEMD@/bin/systemctl list-timers --no-pager agentic-backup.timer 2>/dev/null || true
echo
echo 'GITHUB PROTECTION AUDIT'
audit_status=/var/lib/agentic-github-protection/status
if [ -r "$audit_status" ]; then
  checked="$(@GAWK@/bin/awk -F= '$1 == "checked_at" {print $2; exit}' "$audit_status")"
  result="$(@GAWK@/bin/awk -F= '$1 == "result" {print $2; exit}' "$audit_status")"
  summary="$(@GAWK@/bin/awk -F= '$1 == "summary" {sub(/^[^=]*=/, ""); print; exit}' "$audit_status")"
  now="$(@COREUTILS@/bin/date -u +%s)"
  if [[ "$checked" =~ ^[0-9]+$ && "$result" =~ ^(PASS|FAIL)$ ]] &&
     (( checked <= now && now - checked < 172800 )); then
    printf '  %s: %s\n' "$result" "$summary"
    printf '  Checked: %s UTC\n' "$(@COREUTILS@/bin/date -u -d "@$checked" '+%Y-%m-%d %H:%M')"
  else
    echo '  STALE: no recent valid audit result (older than 48 hours)'
  fi
else
  echo '  NOT RUN: no audit status yet'
fi
echo '  Details: agentic-github-protection-report (no sudo)'
echo '  Run now: sudo systemctl start agentic-github-protection-audit.service'
echo
echo 'FIREWALL (DECLARED GLOBAL ALLOW RULES)'
echo '  Firewall enabled: @FIREWALL@'
echo '  TCP: @TCP_PORTS@'
echo '  UDP: @UDP_PORTS@'
echo '  Note: service and interface-specific exceptions may also apply.'
echo '  These are allowed ports, not a list of listening processes.'
echo
echo 'QUICK COMMANDS'
echo '  cd ~/work           Enter sandbox workspace'
echo '  pi                  Start sandboxed Pi'
echo '  omp                 Start sandboxed Oh My Pi'
echo '  Ctrl+R              Search command history'
echo '  Tab                 Autocomplete'
