{ config, pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  piPkg = inputs.pi.packages.${system}.default;
  nonoPkg = inputs.nono.packages.${system}.prebuilt;
  herdrPkg = inputs.herdr.packages.${system}.default;
  skillsSource = inputs.matt-skills;
  nnpi = pkgs.writeShellApplication {
    name = "nnpi";
    runtimeInputs = [ pkgs.coreutils piPkg nonoPkg herdrPkg ];
    text = ''
      export HERDR_AGENT=pi
      export JITI_FS_CACHE=false
      work_root="$(realpath -e "$HOME/work")"
      current="$(realpath -e "$PWD")"
      case "$current/" in
        "$work_root/"*) ;;
        *) echo "nnpi: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
      esac
      exec ${nonoPkg}/bin/nono run --profile pi-herdr --allow-cwd -- ${piPkg}/bin/pi "$@"
    '';
  };
  tcpPorts = config.networking.firewall.allowedTCPPorts;
  udpPorts = config.networking.firewall.allowedUDPPorts;
  formatPorts = ports: if ports == [] then "none" else lib.concatStringsSep ", " (map toString ports);
  status = pkgs.writeShellScriptBin "agentic-status" ''
    echo 'AGENTIC WORKSPACE'
    echo '  Workspace: ~/work'
    echo '  Switch:    cd ~/work'
    echo '  Start Pi:  nnpi'
    echo
    echo 'AVAILABLE TOOLS'
    for tool in nnpi pi nono herdr git node npm; do
      if command -v "$tool" >/dev/null 2>&1; then
        printf '  %-10s %s\n' "$tool" "$(command -v "$tool")"
      fi
    done
    echo
    echo 'MAINTENANCE'
    ${pkgs.systemd}/bin/systemctl list-timers --no-pager agentic-backup.timer 2>/dev/null || true
    echo
    echo 'FIREWALL (DECLARED GLOBAL ALLOW RULES)'
    echo '  Firewall enabled: ${if config.networking.firewall.enable then "yes" else "no"}'
    echo '  TCP: ${formatPorts tcpPorts}'
    echo '  UDP: ${formatPorts udpPorts}'
    echo '  Note: service and interface-specific exceptions may also apply.'
    echo '  These are allowed ports, not a list of listening processes.'
    echo
    echo 'QUICK COMMANDS'
    echo '  cd ~/work           Enter sandbox workspace'
    echo '  nnpi                Start sandboxed Pi'
    echo '  Ctrl+R              Search command history'
    echo '  Tab                 Autocomplete'
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
  environment.systemPackages = [ nnpi status backup pkgs.ghostty.terminfo piPkg nonoPkg herdrPkg ];

  # Pi discovers recursively under ~/.pi/agent/skills. Install skills via
  # a read-only symlink to the pinned flake source; never mutate the Nix store.
  systemd.services.agentic-skills = {
    description = "Install global Pi skills and agentic nono profile";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -o agentic -g users -m 0755 /home/agentic/.pi/agent/skills
      if [ ! -e /home/agentic/.pi/agent/skills/mattpocock ]; then
        ln -s ${skillsSource} /home/agentic/.pi/agent/skills/mattpocock
      fi
      install -d -o agentic -g users -m 0700 /home/agentic/.config/nono/profiles
      cat > /home/agentic/.config/nono/profiles/pi-herdr.json <<'PROFILE'
      {
        "extends": "nolabs-ai/pi",
        "meta": {"name": "pi-herdr", "version": "1.0.1"},
        "workdir": {"access": "readwrite"},
        "filesystem": {"allow": ["$HOME/work"], "read": ["$HOME/.pi/agent/skills"]}
      }
      PROFILE
      chown agentic:users /home/agentic/.config/nono/profiles/pi-herdr.json
      chmod 0600 /home/agentic/.config/nono/profiles/pi-herdr.json
    '';
  };
  # Registry packs are mutable upstream. They are installed as the agent user,
  # outside the Nix store, and refreshed periodically after a local backup.
  systemd.services.agentic-nono-pack = {
    description = "Refresh reviewed nono Pi registry pack";
    after = [ "agentic-skills.service" "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = { Type = "oneshot"; User = "agentic"; Environment = "HOME=/home/agentic"; };
    script = ''
      ${nonoPkg}/bin/nono pull nolabs-ai/pi
    '';
  };
  systemd.timers.agentic-nono-pack = {
    wantedBy = [ "timers.target" ];
    timerConfig = { OnBootSec = "3min"; OnCalendar = "daily"; RandomizedDelaySec = "30min"; Persistent = true; };
  };

  # Automatic update checks, rather than unreviewed live configuration swaps.
  # The pinned flake is upgraded deliberately from the deployment host.
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nix.optimise.automatic = true;
  system.autoUpgrade.enable = false;
  systemd.tmpfiles.rules = [
    "d /home/agentic/work 0750 agentic users - -"
    "d /var/backups/agentic 0700 root root - -"
  ];
  # Prevent zsh-newuser-install. This creates only the startup file if absent;
  # the global interactive configuration below remains declarative.
  system.userActivationScripts.agenticZshrc = ''
    if [ -d /home/agentic ]; then
      if [ ! -e /home/agentic/.zshrc ]; then
        touch /home/agentic/.zshrc
        chown agentic:users /home/agentic/.zshrc
        chmod 0644 /home/agentic/.zshrc
      fi
    fi
  '';
  programs.zsh.promptInit = lib.mkForce ''
    eval "$(${pkgs.starship}/bin/starship init zsh)"
  '';
  programs.zsh.interactiveShellInit = ''
    export PATH="$HOME/.local/bin:$PATH"
    # Existing systems may lack the Ghostty definition. Keep a safe fallback.
    if [[ "$TERM" == xterm-ghostty ]] && ! ${pkgs.ncurses}/bin/infocmp xterm-ghostty >/dev/null 2>&1; then
      export TERM=xterm-256color
    fi
    if [[ "$(id -un)" == agentic && -z "''${NNPI_WELCOME_SHOWN:-}" && -z "''${NNPI_NO_WELCOME:-}" ]]; then
      export NNPI_WELCOME_SHOWN=1
      ${status}/bin/agentic-status
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
