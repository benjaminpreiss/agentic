{ config, pkgs, lib, inputs, ... }:
let
  system = pkgs.stdenv.hostPlatform.system;
  piPkg = inputs.pi.packages.${system}.default;
  ompPkg = inputs.omp.packages.${system}.default;
  nonoPkg = inputs.nono.packages.${system}.prebuilt;
  herdrPkg = inputs.herdr.packages.${system}.default;
  skillsSource = inputs.matt-skills;
  sandboxedPi = pkgs.writeShellApplication {
    name = "pi";
    runtimeInputs = [ pkgs.coreutils nonoPkg herdrPkg ];
    text = ''
      export HERDR_AGENT=pi
      export JITI_FS_CACHE=false
      work_root="$(realpath -e "$HOME/work")"
      current="$(realpath -e "$PWD")"
      case "$current/" in
        "$work_root/"*) ;;
        *) echo "pi: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
      esac
      exec ${nonoPkg}/bin/nono run --profile pi-herdr --allow-cwd \
        --allow-unix-socket /run/agentic-github-mcp.sock \
        --allow-unix-socket /run/agentic-git-credentials.sock \
        -- ${piPkg}/bin/pi "$@"
    '';
  };
  sandboxedOmp = pkgs.writeShellApplication {
    name = "omp";
    runtimeInputs = [ pkgs.coreutils nonoPkg ];
    text = ''
      work_root="$(realpath -e "$HOME/work")"
      current="$(realpath -e "$PWD")"
      case "$current/" in
        "$work_root/"*) ;;
        *) echo "omp: work inside ~/work; run: cd ~/work" >&2; exit 2 ;;
      esac
      exec ${nonoPkg}/bin/nono run --profile omp-agentic --allow-cwd \
        --allow-unix-socket /run/agentic-git-credentials.sock \
        -- ${ompPkg}/bin/omp "$@"
    '';
  };
  tcpPorts = config.networking.firewall.allowedTCPPorts;
  udpPorts = config.networking.firewall.allowedUDPPorts;
  formatPorts = ports: if ports == [] then "none" else lib.concatStringsSep ", " (map toString ports);
  auditReport = pkgs.writeShellScriptBin "agentic-github-protection-report" ''
    report=/var/lib/agentic-github-protection/report
    if [ ! -r "$report" ]; then
      echo 'No readable GitHub protection audit report yet.' >&2
      exit 1
    fi
    ${pkgs.coreutils}/bin/cat -- "$report"
  '';
  status = pkgs.writeShellScriptBin "agentic-status" ''
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
    ${pkgs.systemd}/bin/systemctl list-timers --no-pager agentic-backup.timer 2>/dev/null || true
    echo
    echo 'GITHUB PROTECTION AUDIT'
    audit_status=/var/lib/agentic-github-protection/status
    if [ -r "$audit_status" ]; then
      checked="$(${pkgs.gawk}/bin/awk -F= '$1 == "checked_at" {print $2; exit}' "$audit_status")"
      result="$(${pkgs.gawk}/bin/awk -F= '$1 == "result" {print $2; exit}' "$audit_status")"
      summary="$(${pkgs.gawk}/bin/awk -F= '$1 == "summary" {sub(/^[^=]*=/, ""); print; exit}' "$audit_status")"
      now="$(${pkgs.coreutils}/bin/date -u +%s)"
      if [[ "$checked" =~ ^[0-9]+$ && "$result" =~ ^(PASS|FAIL)$ ]] &&
         (( checked <= now && now - checked < 172800 )); then
        printf '  %s: %s\n' "$result" "$summary"
        printf '  Checked: %s UTC\n' "$(${pkgs.coreutils}/bin/date -u -d "@$checked" '+%Y-%m-%d %H:%M')"
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
    echo '  Firewall enabled: ${if config.networking.firewall.enable then "yes" else "no"}'
    echo '  TCP: ${formatPorts tcpPorts}'
    echo '  UDP: ${formatPorts udpPorts}'
    echo '  Note: service and interface-specific exceptions may also apply.'
    echo '  These are allowed ports, not a list of listening processes.'
    echo
    echo 'QUICK COMMANDS'
    echo '  cd ~/work           Enter sandbox workspace'
    echo '  pi                  Start sandboxed Pi'
    echo '  omp                 Start sandboxed Oh My Pi'
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
  imports = [ ./github-mcp.nix ];
  # Do not expose the raw agent packages on the system PATH: command discovery
  # must find the sandbox launchers, not an unsandboxed binary.
  environment.systemPackages = [ sandboxedPi sandboxedOmp status auditReport backup pkgs.ghostty.terminfo nonoPkg herdrPkg ];

  # Pi discovers recursively under ~/.pi/agent/skills. Install skills via
  # a read-only symlink to the pinned flake source; never mutate the Nix store.
  systemd.services.agentic-skills = {
    description = "Install global Pi skills and agentic nono profiles";
    wantedBy = [ "multi-user.target" ];
    after = [ "local-fs.target" ];
    serviceConfig = { Type = "oneshot"; RemainAfterExit = true; };
    path = [ pkgs.coreutils ];
    script = ''
      install -d -o agentic -g users -m 0755 /home/agentic/.pi /home/agentic/.pi/agent /home/agentic/.pi/agent/skills
      install -d -o agentic -g users -m 0755 /home/agentic/.config /home/agentic/.config/nono
      install -d -o agentic -g users -m 0700 /home/agentic/.config/nono/profiles
      if [ ! -e /home/agentic/.pi/agent/skills/mattpocock ]; then
        ln -s ${skillsSource} /home/agentic/.pi/agent/skills/mattpocock
      fi
      # Registry state directories are owned by agentic via tmpfiles below.
      # Only install local profiles here; packs are pulled by apply.sh.
      install -o agentic -g users -m 0600 ${../profiles/pi-herdr.json} /home/agentic/.config/nono/profiles/pi-herdr.json
      install -o agentic -g users -m 0600 ${../profiles/omp-agentic.json} /home/agentic/.config/nono/profiles/omp-agentic.json
    '';
  };
  # Automatic update checks, rather than unreviewed live configuration swaps.
  # The pinned flake is upgraded deliberately from the deployment host.
  nix.gc = { automatic = true; dates = "weekly"; options = "--delete-older-than 30d"; };
  nix.optimise.automatic = true;
  system.autoUpgrade.enable = false;
  systemd.tmpfiles.rules = [
    "d /home/agentic/work 0750 agentic users - -"
    "d /home/agentic/.pi 0755 agentic users - -"
    "d /home/agentic/.pi/agent 0755 agentic users - -"
    "z /home/agentic/.pi 0755 agentic users - -"
    "z /home/agentic/.pi/agent 0755 agentic users - -"
    "d /home/agentic/.config 0755 agentic users - -"
    "d /home/agentic/.config/nono 0755 agentic users - -"
    "d /home/agentic/.config/nono/profiles 0700 agentic users - -"
    "d /home/agentic/.config/nono/packages 0700 agentic users - -"
    "d /home/agentic/.config/nono/profile-drafts 0700 agentic users - -"
    "d /var/backups/agentic 0700 root root - -"
  ];
  # Prevent zsh-newuser-install. This creates the startup file only if absent;
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
    # Agent launchers take precedence even if a user installed raw binaries
    # under ~/.local/bin. Other user tools remain available there.
    export PATH="${sandboxedPi}/bin:${sandboxedOmp}/bin:$HOME/.local/bin:$PATH"
    # Existing systems may lack the Ghostty definition. Keep a safe fallback.
    if [[ "$TERM" == xterm-ghostty ]] && ! ${pkgs.ncurses}/bin/infocmp xterm-ghostty >/dev/null 2>&1; then
      export TERM=xterm-256color
    fi
    if [[ "$(id -un)" == agentic && -z "''${AGENTIC_WELCOME_SHOWN:-}" && -z "''${AGENTIC_NO_WELCOME:-}" ]]; then
      export AGENTIC_WELCOME_SHOWN=1
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
