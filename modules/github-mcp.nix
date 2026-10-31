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
