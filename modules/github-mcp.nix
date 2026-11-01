{ pkgs, lib, ... }:
let
  socketPath = "/run/agentic-github-mcp.sock";

  # The github-mcp-server package in our current nixpkgs is 1.1.2 and does
  # not implement GitHub App authentication. Use the official v2.0.3 binary
  # with its fixed SHA-256. Do not put private keys in the Nix store.
  githubMcpServer = pkgs.stdenvNoCC.mkDerivation {
    pname = "github-mcp-server";
    version = "2.0.3";
    src = pkgs.fetchurl {
      url = "https://github.com/github/github-mcp-server/releases/download/v2.0.3/github-mcp-server_Linux_x86_64.tar.gz";
      hash = "sha256-95fCD+AqdVhl0OLUYYSrR+Mb8WGbCFW42JxTHkWmUcI=";
    };
    dontUnpack = true;
    nativeBuildInputs = [ pkgs.gnutar pkgs.gzip pkgs.findutils ];
    installPhase = ''
      runHook preInstall
      mkdir -p "$out/bin" "$TMPDIR/github-mcp-unpack"
      tar -xzf "$src" -C "$TMPDIR/github-mcp-unpack"
      binary="$(find "$TMPDIR/github-mcp-unpack" -type f -name github-mcp-server -print -quit)"
      if [ -z "$binary" ]; then
        echo "GitHub MCP release did not contain github-mcp-server" >&2
        exit 1
      fi
      install -m 0755 "$binary" "$out/bin/github-mcp-server"
      runHook postInstall
    '';
    meta = {
      description = "Official GitHub MCP server with GitHub App authentication";
      homepage = "https://github.com/github/github-mcp-server";
      platforms = [ "x86_64-linux" ];
      mainProgram = "github-mcp-server";
    };
  };
  # The audit runs from the pinned Nix store, outside the coding-agent sandbox.
  # The PEM and App IDs are passed only to this service through systemd credentials.
  protectionAudit = pkgs.writeShellApplication {
    name = "agentic-github-protection-audit";
    runtimeInputs = with pkgs; [ bash curl jq openssl coreutils gnused gnugrep ];
    text = ''
      umask 077
      state=/var/lib/agentic-github-protection
      tmp="$(mktemp "$state/.status.XXXXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      checked="$(date -u +%s)"
      if output="$(AGENTIC_GITHUB_SECRETS_DIR="''${CREDENTIALS_DIRECTORY:?}" ${pkgs.bash}/bin/bash ${../github-protection}/check.sh 2>&1)"; then
        result=PASS
      else
        result=FAIL
      fi
      printf '%s\n' "$output"
      summary="$(printf '%s\n' "$output" | grep '^Summary:' | tail -n 1 || true)"
      summary="''${summary:-Audit failed before summary}"
      printf 'checked_at=%s\nresult=%s\nsummary=%s\n' "$checked" "$result" "$summary" > "$tmp"
      chmod 0644 "$tmp"
      mv -f "$tmp" "$state/status"
      [[ "$result" == PASS ]]
    '';
  };
  gitSocketPath = "/run/agentic-git-credentials.sock";
  # This process runs outside nono. Only a per-repository installation token,
  # never the PEM, crosses the socket into Git. One App may have many installations.
  gitTokenBroker = pkgs.writeShellApplication {
    name = "agentic-git-token-broker";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.openssl pkgs.curl ];
    text = builtins.readFile ../scripts/git-app-token-broker.sh;
  };
  gitCredentialHelper = pkgs.writeShellApplication {
    name = "agentic-git-credential";
    runtimeInputs = [ pkgs.socat ];
    text = builtins.readFile ../scripts/git-credential-helper.sh;
  };
  configureGitCredentials = pkgs.writeShellApplication {
    name = "agentic-configure-git-credentials";
    runtimeInputs = [ pkgs.git ];
    text = builtins.readFile ../scripts/configure-git-credentials.sh;
  };
  mcpEntry = builtins.toJSON {
    command = "${pkgs.socat}/bin/socat";
    args = [ "STDIO" "UNIX-CONNECT:${socketPath}" ];
    description = "GitHub repositories, issues, pull requests and CI via the official GitHub MCP server";
    exposure = "deferred";
  };
  configurePi = pkgs.writeShellApplication {
    name = "agentic-configure-github-mcp";
    runtimeInputs = [ pkgs.jq pkgs.coreutils ];
    text = ''
      set -euo pipefail
      config="$HOME/.pi/agent/mcp.json"
      mkdir -p "$(dirname "$config")"
      tmp="$(mktemp "$(dirname "$config")/.mcp.json.XXXXXXXX")"
      trap 'rm -f "$tmp"' EXIT
      if [ -e "$config" ]; then
        ${pkgs.jq}/bin/jq --argjson github '${mcpEntry}' \
          '.mcpServers = (.mcpServers // {}) | .mcpServers.github = $github' \
          "$config" > "$tmp"
      else
        ${pkgs.jq}/bin/jq -n --argjson github '${mcpEntry}' \
          '{mcpServers: {github: $github}}' > "$tmp"
      fi
      chmod 0600 "$tmp"
      mv -f "$tmp" "$config"
    '';
  };
in {
  systemd.services.agentic-github-protection-audit = {
    description = "Read-only protection audit for all repositories in the GitHub App installation";
    after = [ "network-online.target" ];
    wants = [ "network-online.target" ];
    serviceConfig = {
      Type = "oneshot";
      LoadCredential = [
        "app.env:/etc/agentic/github-app/app.env"
        "private-key.pem:/etc/agentic/github-app/private-key.pem"
      ];
      StateDirectory = "agentic-github-protection";
      StateDirectoryMode = "0755";
      ExecStart = "${protectionAudit}/bin/agentic-github-protection-audit";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_INET" "AF_INET6" ];
    };
  };
  systemd.timers.agentic-github-protection-audit = {
    description = "Daily GitHub protection audit";
    wantedBy = [ "timers.target" ];
    timerConfig = { OnCalendar = "*-*-* 03:00:00"; RandomizedDelaySec = "15min"; Persistent = true; };
  };
  # The listener is owned by systemd, not by Pi. Each accepted connection
  # spawns a dedicated official github-mcp-server stdio process.
  systemd.sockets.agentic-github-mcp = {
    description = "GitHub MCP local transport for agentic";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = socketPath;
      Accept = true;
      SocketUser = "agentic";
      SocketGroup = "users";
      SocketMode = "0600";
      RemoveOnStop = true;
    };
  };
  systemd.services."agentic-github-mcp@" = {
    description = "Official GitHub MCP server (per connection)";
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      EnvironmentFile = "/etc/agentic/github-app/app.env";
      LoadCredential = "github-app.pem:/etc/agentic/github-app/private-key.pem";
      Environment = [ "GITHUB_APP_PRIVATE_KEY_PATH=%d/github-app.pem" ];
      ExecStart = "${githubMcpServer}/bin/github-mcp-server stdio";
      StandardInput = "socket";
      StandardOutput = "inherit";
      StandardError = "journal";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    };
  };
  # A separate, agentic-only socket serves Git's HTTPS credential helper.
  # No App key or long-lived credential is available inside nono.
  systemd.sockets.agentic-git-credentials = {
    description = "GitHub App installation tokens for agentic Git pushes";
    wantedBy = [ "sockets.target" ];
    socketConfig = {
      ListenStream = gitSocketPath;
      Accept = true;
      SocketUser = "agentic";
      SocketGroup = "users";
      SocketMode = "0600";
      RemoveOnStop = true;
    };
  };
  systemd.services."agentic-git-credentials@" = {
    description = "Mint a scoped GitHub App token for one Git credential request";
    serviceConfig = {
      Type = "simple";
      DynamicUser = true;
      EnvironmentFile = "/etc/agentic/github-app/app.env";
      LoadCredential = "github-app.pem:/etc/agentic/github-app/private-key.pem";
      ExecStart = "${gitTokenBroker}/bin/agentic-git-token-broker";
      StandardInput = "socket";
      StandardOutput = "inherit";
      StandardError = "journal";
      NoNewPrivileges = true;
      ProtectSystem = "strict";
      ProtectHome = true;
      PrivateTmp = true;
      ProtectKernelTunables = true;
      ProtectKernelModules = true;
      ProtectControlGroups = true;
      RestrictSUIDSGID = true;
      LockPersonality = true;
      CapabilityBoundingSet = "";
      RestrictAddressFamilies = [ "AF_UNIX" "AF_INET" "AF_INET6" ];
    };
  };
  systemd.services.agentic-configure-git-credentials = {
    description = "Configure agentic Git credential helper for GitHub HTTPS repositories";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agentic";
      Group = "users";
      Environment = "HOME=/home/agentic";
      ExecStart = "${configureGitCredentials}/bin/agentic-configure-git-credentials ${gitCredentialHelper}/bin/agentic-git-credential ${gitSocketPath}";
    };
  };
  # Merge only the github MCP entry; do not replace unrelated servers.
  # This runs as agentic so mcp.json stays writable by Pi.
  systemd.services.agentic-configure-github-mcp = {
    description = "Configure Pi built-in MCP for GitHub";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agentic";
      Group = "users";
      Environment = "HOME=/home/agentic";
      ExecStart = "${configurePi}/bin/agentic-configure-github-mcp";
    };
  };
}
