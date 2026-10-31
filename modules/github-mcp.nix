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
  gitSocketPath = "/run/agentic-git-credentials.sock";
  # This process runs outside nono. Only the installation token, never the PEM,
  # crosses the socket into Git. Request the minimum permissions for git push.
  gitTokenBroker = pkgs.writeShellApplication {
    name = "agentic-git-token-broker";
    runtimeInputs = [ pkgs.coreutils pkgs.jq pkgs.openssl pkgs.curl ];
    text = ''
      set -euo pipefail
      IFS= read -r request || exit 1
      [[ "$request" == token ]] || exit 1
      [[ "''${GITHUB_APP_ID:-}" =~ ^[0-9]+$ && "''${GITHUB_APP_INSTALLATION_ID:-}" =~ ^[0-9]+$ ]] || exit 1
      key="''${CREDENTIALS_DIRECTORY:?}/github-app.pem"
      now="$(date +%s)"
      b64url() { base64 | tr -d '\r\n' | tr '+/' '-_' | tr -d '='; }
      header='eyJhbGciOiJSUzI1NiIsInR5cCI6IkpXVCJ9'
      payload="$(jq -cn --argjson iat "$((now-60))" --argjson exp "$((now+540))" --arg iss "$GITHUB_APP_ID" '{iat:$iat,exp:$exp,iss:$iss}' | b64url)"
      unsigned="$header.$payload"
      signature="$(printf %s "$unsigned" | openssl dgst -sha256 -sign "$key" | b64url)"
      jwt="$unsigned.$signature"
      # Neither curl output nor its request headers are logged. A non-201
      # response yields no credential; tokens are never written to disk.
      response="$(curl --silent --show-error --max-time 30 --request POST \
        --header "Authorization: Bearer $jwt" \
        --header 'Accept: application/vnd.github+json' \
        --header 'X-GitHub-Api-Version: 2022-11-28' \
        --header 'Content-Type: application/json' \
        --data '{"repositories":["agentic"],"permissions":{"contents":"write"}}' \
        --write-out '\n%{http_code}' \
        "https://api.github.com/app/installations/$GITHUB_APP_INSTALLATION_ID/access_tokens")"
      [[ "''${response##*$'\n'}" == 201 ]] || exit 1
      body="''${response%$'\n'*}"
      token="$(jq -er '.token | select(type == "string" and test("^[A-Za-z0-9_]+$"))' <<<"$body")"
      printf '%s\n' "$token"
    '';
  };
  gitCredentialHelper = pkgs.writeShellApplication {
    name = "agentic-git-credential";
    runtimeInputs = [ pkgs.socat ];
    text = ''
      set -euo pipefail
      [[ "''${1:-}" == get ]] || exit 0
      protocol= host= path=
      while IFS= read -r line && [[ -n "$line" ]]; do
        case "$line" in
          protocol=*) protocol="''${line#protocol=}" ;;
          host=*) host="''${line#host=}" ;;
          path=*) path="''${line#path=}" ;;
        esac
      done
      # Fail closed for other repositories, protocols, or hosts.
      [[ "$protocol" == https && "$host" == github.com && "$path" == benjaminpreiss/agentic.git ]] || exit 0
      token="$(printf 'token\n' | socat - "UNIX-CONNECT:${gitSocketPath}")" || exit 1
      [[ "$token" =~ ^[A-Za-z0-9_]+$ ]] || exit 1
      printf 'username=x-access-token\npassword=%s\n\n' "$token"
    '';
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
    description = "Configure agentic Git credential helper for this repository";
    wantedBy = [ "multi-user.target" ];
    after = [ "systemd-tmpfiles-setup.service" ];
    serviceConfig = {
      Type = "oneshot";
      User = "agentic";
      Group = "users";
      Environment = "HOME=/home/agentic";
    };
    path = [ pkgs.git ];
    script = ''
      set -euo pipefail
      key=credential.https://github.com/benjaminpreiss/agentic.git.helper
      git config --global --unset-all "$key" || true
      # An empty helper resets inherited helpers for this URL.
      git config --global --add "$key" ""
      git config --global --add "$key" "${gitCredentialHelper}/bin/agentic-git-credential"
      git config --global credential.https://github.com/benjaminpreiss/agentic.git.useHttpPath true
    '';
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
