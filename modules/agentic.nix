{ pkgs, lib, ... }:
let
  nnpi = pkgs.writeShellApplication {
    name = "nnpi";
    runtimeInputs = with pkgs; [ coreutils ];
    text = ''
      export HERDR_AGENT=pi
      export JITI_FS_CACHE=false
      work_root="$(realpath -e "$HOME/work")"
      current="$(realpath -e "$PWD")"
      case "$current/" in
        "$work_root/"*) ;;
        *) echo "nnpi: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
      esac
      command -v nono >/dev/null || { echo 'nono not installed; see docs/POSTINSTALL.md' >&2; exit 127; }
      command -v pi >/dev/null || { echo 'pi not installed; see docs/POSTINSTALL.md' >&2; exit 127; }
      exec nono run --profile pi-herdr --allow-cwd -- pi "$@"
    '';
  };
  status = pkgs.writeShellScriptBin "agentic-status" ''
    echo 'AGENTIC WORKSPACE'
    echo '  Workspace: ~/work'
    echo '  Switch:    cd ~/work'
    echo '  Start Pi:  nnpi'
    echo
    echo 'MAINTENANCE'
    ${pkgs.systemd}/bin/systemctl list-timers --no-pager agentic-backup.timer 2>/dev/null || true
    echo 'FIREWALL (NixOS configuration)'
    ${pkgs.iproute2}/bin/ss -lnt 2>/dev/null | head -12 || true
  '';
  backup = pkgs.writeShellApplication {
    name = "agentic-backup";
    runtimeInputs = with pkgs; [ coreutils gnutar gzip findutils ];
    text = ''
      umask 077
      store=/var/backups/agentic
      mkdir -p "$store"
      test -d /home/agentic || exit 1
      stamp="$(date -u +%Y%m%dT%H%M%SZ)"
      tmp="$store/agentic-$stamp-$$.tar.gz.partial"
      dest="''${tmp%.partial}"
      trap 'rm -f "$tmp"' EXIT
      tar -C /home -czpf "$tmp" --one-file-system agentic
      gzip -t "$tmp"
      mv "$tmp" "$dest"
      find "$store" -maxdepth 1 -name 'agentic-*.tar.gz' -type f -printf '%f\n' | sort -r | tail -n +15 | while IFS= read -r old; do rm -f -- "$store/$old"; done
      echo "Backup completed: $dest"
    '';
  };
in {
  environment.systemPackages = [ nnpi status backup ];
  systemd.tmpfiles.rules = [
    "d /home/agentic/work 0750 agentic users - -"
    "d /var/backups/agentic 0700 root root - -"
  ];
  programs.zsh.interactiveShellInit = ''
    export PATH="$HOME/.local/bin:$PATH"
    if [[ "$TERM" == xterm-ghostty ]] && ! infocmp xterm-ghostty >/dev/null 2>&1; then export TERM=xterm-256color; fi
    if [[ "$(id -un)" == agentic && -z "''${NNPI_WELCOME_SHOWN:-}" && -z "''${NNPI_NO_WELCOME:-}" ]]; then
      export NNPI_WELCOME_SHOWN=1
      agentic-status
    fi
  '';
  systemd.services.agentic-backup = {
    description = "Back up agentic home directory locally";
    serviceConfig = { Type = "oneshot"; ExecStart = "${backup}/bin/agentic-backup"; User = "root"; };
  };
  systemd.timers.agentic-backup = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:30:00"; RandomizedDelaySec = "20min"; Persistent = true; };
  };
}
