# GitHub access for the NixOS agent

This guide sets up a GitHub App for sandboxed Pi: the official MCP server provides read access to issues and PRs, while a host-side Git credential broker supplies short-lived tokens for HTTPS pushes. The private key stays outside Pi's sandbox and the Nix store.

**Security policy:** agents can push work branches (for example `agentic/*`). The repository's default branch requires a PR, approval, fresh approval after new commits, and checks. The App cannot enforce a specific reviewer through GitHub rulesets alone. **Do not grant agents unrestricted PR-write or Issues-write access** until a separate trusted mutation service exists; this repository does not provide one. Do not treat the current unfiltered MCP server as a merge authorization gate.

## 1. Create and install the App

[Open the prefilled registration form](https://github.com/settings/apps/new?name=agentic-workbox&description=Sandboxed%20coding%20agents%20with%20gated%20merges&url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=read&issues=read&actions=read&checks=read&statuses=read), or edit an existing App in [GitHub App settings](https://github.com/settings/apps). Choose a **private App**, disable webhooks and OAuth on installation, and confirm these repository permissions:

| Permission | Level |
| --- | --- |
| Contents | Read & write (Git pushes) |
| Pull requests, Issues | Read-only for agents |
| Actions, Checks, Commit statuses | Read-only |
| Metadata | Read-only (automatic) |
| Workflows, Administration, Secrets, Environments | No access |

Install it on **Only select repositories**, starting with `benjaminpreiss/agentic`. On the App's General page, record its **App ID**, download a private key (`.pem`), and record the **installation ID**. Never paste the key into chat or commit it. One App can cover several repositories/installations; the MCP server uses the configured installation ID, while Git looks up the installation for each repository. Multiple different Apps at once are not supported.

## 2. Protect the default branch

In each repository, use **Settings → Rules → Rulesets** and follow [the recommended rulesets](recommended-rulesets.md). Confirm the App has **no bypass privileges**. GitHub rulesets cannot require approval from *benjaminpreiss* specifically; enforcing a particular reviewer's identity would require a separate trusted merge service.

## 3. Prepare private credentials locally

On your deployment computer, from this repository's root, move the downloaded PEM into `secrets/github-app/` and select it with a symlink:

```bash
mkdir -p secrets/github-app
mv ~/Downloads/YOUR-GITHUB-APP-KEY.pem secrets/github-app/
chmod 600 secrets/github-app/YOUR-GITHUB-APP-KEY.pem
ln -sfn YOUR-GITHUB-APP-KEY.pem secrets/github-app/private-key.pem
bash scripts/github/configure-github-app.sh
```

Replace the example filename with the real one. The script prompts for the App ID and installation ID and creates `secrets/github-app/app.env`. The symlink **must resolve to a PEM inside this directory**. For key rotation, change the symlink and rerun `scripts/update/apply.sh`.

**Never put keys or tokens in `.deployment/`, Nix expressions, Git history, or a published archive.** Both `secrets/` and `.deployment/` are Git-ignored; inspect staged files before committing anyway. Credentials are uploaded separately from the flake source.

## 4. Audit the rules, then deploy

From your deployment computer:

```bash
bash github-protection/check.sh
# Optional exhaustive scan of effective branch rules:
bash github-protection/check.sh --all-branches
```

The read-only audit uses the configured installation's key and checks **every repository accessible to that installation**, not other installations. It examines the actual default branch, its applicable rulesets, and a sample work branch. Run `--all-branches` for a fuller scan. It checks PR, squash, approval, stale-review and force-push/deletion rules; it warns about missing CI checks based on the default branch's *current tip*, which may not show PR-only checks. ✅ means a pass, ⚠️ a warning (not a failure), and ❌ a blocking failure. Run credential-free fixtures with `bash github-protection/test.sh` when audit code changes.

**An audit is not enforcement.** It cannot create rulesets, prove the identity of a reviewer, or always see bypass actors with the App's limited permissions. A zero exit status can still include warnings. Have an administrator inspect repository and organization rulesets and bypass actors; resolve blocking findings before deploying. Protect repositories in other installations separately.

Use the non-destructive update path for an already installed NixOS machine:

```bash
bash scripts/update/apply.sh
```

The helper evaluates the system and runs `nixos-rebuild switch` without formatting disks. It uploads local App credentials over SSH to root-owned `/etc/agentic/github-app/{app.env,private-key.pem}`, outside the Nix flake source. **Never rerun the fresh disk installer to add GitHub access.** See [the update guide](update.md).

## 5. Verify the server and permissions

From an administrative shell on the server:

```bash
systemctl status agentic-github-mcp.socket agentic-git-credentials.socket --no-pager
sudo stat -c '%a %U:%G %n' /etc/agentic/github-app/app.env /etc/agentic/github-app/private-key.pem
sudo systemctl start agentic-github-protection-audit.service
```

The credential files should show `600 root:root`. The scheduled `agentic-github-protection-audit.timer` repeats the audit daily; `agentic-status` shows PASS, FAIL, STALE or NOT RUN without making a network request at login. Run `agentic-github-protection-report` as `agentic` for the last filtered findings, or inspect `sudo journalctl -u agentic-github-protection-audit.service -n 100 --no-pager` for operational errors. The status does not notify anyone who never logs in. Deploy and verify this timer **before** removing an existing Actions schedule, to avoid a monitoring gap.

As `agentic`, verify the helper path without printing a token:

```bash
git config --global --get-all credential.https://github.com.helper
cd ~/work
pi
```

Test that Pi can read the selected repository through MCP; a listening socket does not prove the transport works. From a GitHub **HTTPS** checkout, push a disposable `agentic/*` branch. Check that direct pushes to the default branch fail, that approval and passing checks are needed to merge there, and that a new commit dismisses stale approval. Record tests you could not perform. The Git token socket does not grant Git's HTTPS network access; if a push cannot reach GitHub, check nono's decision inside the sandbox with `nono why --self --host github.com --port 443`.

## What this access can and cannot do

```text
Pi (inside nono) ── MCP socket ──> host MCP server ──> GitHub reads
Pi's Git helper   ── token socket ──> host broker ──> repo-scoped push token
                                        ↑
                              root-owned App private key
```

Systemd starts a host-side process per socket connection and passes it the key; the key never enters Pi. Git receives a short-lived, repository-scoped Contents-write token. **Any process with access to the token socket can request a token for an installed repository**; the helper does not restrict branch names. The App's permissions are repository-wide. When nono pathname-socket mediation is disabled, `--allow-unix-socket` alone is not an enforced restriction. Never print a token with `git credential fill`, enable credential tracing, or embed tokens in remote URLs. This setup supports GitHub HTTPS, not SSH or GitHub Enterprise; pushing workflow files may require additional Workflows permission, deliberately omitted here.

The official MCP server authenticates Apps in `stdio` mode; its `http` mode does not provide the same built-in flow. **Trusted PR merge and label-scoped issue mutation are not implemented.** A future separate service would need to check the PR base and current head, the named reviewer's non-dismissed approval, required checks and expected head SHA immediately before merging. Issue mutations would need to check the `agentic` label and issue identity on each write. Neither service should expose its write credentials to Pi or the Git token socket. Until then, agents should not receive unrestricted PR/Issues-write access by MCP, raw token or another installation.

Further reading: [GitHub MCP App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md), [GitHub rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository).
