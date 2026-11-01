# Agentic — GitHub App setup

This guide sets up **GitHub's official MCP server** and a **Git HTTPS credential helper** for the NixOS coding VPS, with GitHub App credentials supplied from your Mac. Pi runs inside nono; the MCP server and token broker keep the App private key outside the sandbox. Git receives a short-lived token scoped to the repository being pushed. The Git helper supports repositories on `github.com` where this **one GitHub App** is installed, including multiple installations of the same App; simultaneous use of multiple different GitHub Apps is not supported.

**Target-branch policy:** agents push to work branches such as `agentic/*`; the default branch requires a PR, approval, stale-review dismissal, and required checks. All other branches, including the exact `agentic` branch, are directly writable work branches. Native rulesets cannot require a named reviewer.

> The older custom Go/Python GitHub API broker and `agentic-gh` CLI are **not part of this setup**. GitHub rulesets alone cannot enforce the named-reviewer policy. The unfiltered official MCP server and Git credential broker are **not safe merge authorization boundaries**; do not give agents unrestricted PR-write or issue-write credentials if this policy is required.

## 1. Create the GitHub App

**[Open the prefilled GitHub App registration form](https://github.com/settings/apps/new?name=agentic-workbox&description=Sandboxed%20coding%20agents%20with%20gated%20merges&url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=read&issues=read&actions=read&checks=read&statuses=read)**

Review the prefilled settings before submitting. If you already created the App, open [GitHub App settings](https://github.com/settings/apps) to edit the existing App instead; the registration link creates a **new** App.

Recommended repository permissions:

| Permission | Level | Purpose |
|---|---|---|
| Contents | Read & write | Read code, create commits, update branches |
| Pull requests | Read-only for agents | A trusted merge service must hold write access and check target branch, current owner approval, checks and expected head SHA immediately before merging. Separate restricted PR creation if needed. |
| Issues | Read-only for agents | If label-scoped mutations are required, a trusted service must check the `agentic` label immediately before each close/move; no alternate write token. |
| Actions | Read-only | Inspect workflow runs |
| Checks | Read-only | Inspect CI results |
| Commit statuses | Read-only | Inspect statuses |
| Metadata | Read-only (automatic) | Required by GitHub |
| Workflows, Administration, Secrets, Environments | No access | Limit privileges |
| Others | No access initially | Add only if needed |

Choose a **private App**. Leave **webhooks disabled** and **OAuth on installation disabled** for this headless setup. GitHub App permissions are repository-scoped, not branch-scoped; enabling Contents write does **not** restrict the App to `agentic/*`. Do not reuse the agent's App as the trusted merge/issue service identity.

## 2. Install the App

1. In the App settings, click **Install App**.
2. Choose the GitHub account owning the repository.
3. Select **Only select repositories**.
4. Choose `benjaminpreiss/agentic` initially.
5. Complete installation.

On the App's **General** page, record the **App ID** and generate/download a **private key** (`.pem`). Also record the **installation ID** associated with the installation. Never paste the PEM into chat, Pi, or the repository.

## 3. Prepare target branches

Protect the repository's default branch with a default-branch ruleset. All other branches, including `agentic/*` and any legacy exact `agentic` branch, are directly writable work branches. Do not apply a PR requirement to work branches.

```text
any-work-branch ── optional PR or direct push ──> another work branch
any-work-branch ── PR + approval + checks ──> default branch
```

## 4. Audit branch protection for the configured installation

After completing credential setup in section 6, run this **read-only** audit on your Mac from the project root:

```bash
bash github-protection/check.sh
```

The audit prints **✅ for every passing check**, **⚠️ for warnings** (such as missing CI), and **❌ for blocking failures**, with a summary and nonzero exit status if any blocking check fails. **Warnings alone succeed** and do not create a failure alert.

The Bash script requires `curl`, `jq`, `openssl`, `base64`, and standard macOS command-line utilities. It uses your GitHub App ID, installation ID and selected PEM from `secrets/github-app/`. It creates a short-lived installation token **in memory** and lists **every repository accessible to the configured installation** (including paginated results). For each repository the default audit inspects applicable repository/parent rulesets, its actual default branch (from GitHub repository metadata), and one existing work branch from the first 100 branch names. Use `bash github-protection/check.sh --all-branches` locally for an exhaustive effective-rules scan. The audit does not cover other installations of the same App; audit and protect those repositories separately. No permanent token is saved; no rulesets are changed.

`github-protection/check.sh` orchestrates the audit; `github-api.sh` handles App authentication and GitHub reads, and `ci.sh` inventories default-branch-tip checks. Branch-level policy lives in `github-protection/policy.jq`; `github-protection/rulesets.jq` conservatively checks ruleset coverage for **future branches**. Run credential-free fixtures with `bash github-protection/test.sh`. To prove protection follows default-branch renames without covering work branches, it requires an active branch ruleset targeting exactly `~DEFAULT_BRANCH` with no exclusions for squash-only PRs, at least one approval, and stale-review dismissal. A separate active `~ALL` ruleset with no exclusions must block force pushes and deletion on all branches. Any other active PR ruleset is flagged as potentially blocking direct work-branch pushes; even an exact-name rule is not accepted as a rename-safe proof. The audit checks effective rules on the actual default branch and samples a work branch for unexpected PR requirements. These are conservative checks: other valid patterns may be reported as unproven. There is **no requirement to disable merge or rebase methods repository-wide**.

It checks for required PRs, at least one required approval and dismissal of stale approvals after new commits on the default branch, plus protection against force pushes and deletion on all branches. Work branches should permit direct pushes; this audit does not require PRs or approvals on them. It also prints **required/available CI checks** for the default branch (for example `1/2` or `2/2`). “Available” means distinct check runs and commit status contexts observed on the default branch's **current tip commit**; “required” is the number of those observed contexts selected by effective branch rules. `2/2` counts as a pass; `1/2` and `0/0` are warnings, not blocking failures. Checks that only run on PRs may not appear on a branch tip, so this is a snapshot, not a complete CI inventory. Missing branches, required protection rules, and API errors still fail the audit. An exit code of `0` means no blocking findings were detected; **warnings can still be present**.

**IMPORTANT:** An audit is not enforcement. The script **does not create rulesets**; pattern inspection can only prove coverage for the limited ruleset shapes described above, and effective rules do not prove reviewer identity or merge authorization. Bypass actors may be hidden without ruleset write access; the audit warns when it cannot inspect them and flags a visible App bypass actor. A native approval count cannot require *benjaminpreiss* specifically. Even a passing audit is **not proof** of authorization. Inspect bypass actors for every applicable repository/organization ruleset with an administrator, and protect future branches via wildcard rulesets. Never treat the current unfiltered MCP PR-write route as compliant.

For the recommended two-ruleset layout, see [Recommended GitHub branch rulesets](docs/RECOMMENDED_RULESETS.md). To fix missing protections: on GitHub, open the affected repository and navigate to **Settings → Rules → Rulesets → New branch ruleset**. Apply **Active** rulesets matching the audit's missing requirements. Require approval and stale-review dismissal on the default branch only in this audited ruleset. Select **Default branch** (`~DEFAULT_BRANCH`) as the ruleset target, not a literal `main` pattern or all branches; remove or narrow any other PR rules that may affect work branches. When CI workflows have run, select their status checks in each ruleset; the audit will stop warning about missing CI. Re-run the audit after fixing blocking findings.

### Scheduled audit on the server

After deploying this NixOS configuration and the existing `/etc/agentic/github-app/` credentials, `agentic-github-protection-audit.timer` runs daily at 03:00 (up to 15 minutes of jitter, with catch-up after downtime). A root-owned, hardened oneshot service runs the **pinned Nix store version** of the audit outside the agent sandbox, loading App IDs and PEM via systemd credentials. It audits every repository in the configured installation, not just this repo. It persists a root-owned, publicly readable timestamped summary in `/var/lib/agentic-github-protection/status` and a filtered findings report in `/var/lib/agentic-github-protection/report`; neither contains the PEM, token, raw API responses, or raw stderr. Failures give the service a nonzero result; warnings alone succeed. The interactive `agentic-status` welcome screen displays PASS, FAIL, STALE (older than 48 hours), or NOT RUN without making a GitHub request during login. Journal output is available to administrators; the welcome screen does not notify anyone who never logs in.

**Run once immediately on the server:** `sudo systemctl start agentic-github-protection-audit.service`. Then log in again or run `agentic-status` to see the summary. **Without sudo**, run `agentic-github-protection-report` as `agentic` for the last audit's repository findings and summary. For operational errors not included in the filtered report, an administrator can still use `sudo journalctl -u agentic-github-protection-audit.service -n 100 --no-pager`. The original `bash github-protection/check.sh` and `--all-branches` commands still work locally with `secrets/github-app/` (or `AGENTIC_GITHUB_SECRETS_DIR` pointing to another private directory).

`.github/workflows/github-protection-audit.yml` should retain only credential-free `policy-tests` on relevant PR changes. The coding App cannot push workflow edits, so the owner must apply the workflow file on the PR branch. **Deploy and verify the server timer before removing the existing Actions schedule** to avoid a monitoring gap; until that workflow change is merged, both scheduled audits may run. Run `bash github-protection/test.sh` locally without credentials when the audit code changes. A paths-filtered check should not be required for unrelated PRs, since GitHub can leave it pending.

For GitHub API details see [active branch rules](https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch) and [installation repositories](https://docs.github.com/en/rest/apps/installations#list-repositories-accessible-to-the-app-installation).

## 6. Enter credentials once on your Mac

When you create the GitHub App and download its private key, **save the PEM file directly inside `secrets/github-app/` on your Mac**. Keep its original GitHub-generated filename. You can store multiple PEM files there for key rotation.

From the root of your local `agentic` project, create the folder if necessary:

```bash
mkdir -p secrets/github-app
```

Move the downloaded PEM into that folder, for example:

```bash
mv ~/Downloads/agentic-workbox.2026-10-30.private-key.pem secrets/github-app/
chmod 600 secrets/github-app/agentic-workbox.2026-10-30.private-key.pem
```

Replace the example filename with the actual name GitHub gave you. **Select which key is active** by creating a symbolic link (called an alias in Finder) named `private-key.pem`:

```bash
cd secrets/github-app
ln -sfn agentic-workbox.2026-10-30.private-key.pem private-key.pem
cd ../..
```

The result looks like this:

```text
secrets/github-app/
├── agentic-workbox.2026-10-30.private-key.pem
├── agentic-workbox.2026-12-01.private-key.pem
├── private-key.pem -> agentic-workbox.2026-10-30.private-key.pem
└── app.env                         # created in the next step
```

Check which key is currently selected:

```bash
readlink secrets/github-app/private-key.pem
```

Now configure the App IDs:

```bash
bash scripts/configure-github-app.sh
```

The script asks only for the **App ID** and **installation ID**. It reads the selected key through the `private-key.pem` link and creates `secrets/github-app/app.env`. To rotate keys later, change the symlink and rerun `bash scripts/apply.sh`.

**The alias must point to an actual PEM file inside `secrets/github-app/`, not an external path.** The updated deployment script dereferences the alias during SSH transfer, so the VPS receives an ordinary `private-key.pem` file containing the active key, not a broken symlink.

Keep `/secrets/` and `/.deployment/` excluded from Git and from any published ZIP. Never copy the PEM into `flake.nix`, Nix modules, or Nix derivations: Nix may copy evaluated source files into the readable `/nix/store`.

## 7. Deploy from your Mac

With the **GitHub MCP automatic-credentials** files integrated into your local project:

```bash
bash scripts/apply.sh
```

The updated deployment should transfer the local App files over SSH to the VPS and install them as root-owned credentials outside the Nix flake source. Expected server paths:

```text
/etc/agentic/github-app/app.env
/etc/agentic/github-app/private-key.pem
```

The GitHub MCP service must use systemd credential provisioning for the private key. Do not grant Pi or nono access to the PEM, or place the PEM in `.deployment`'s flake source tree. **Do not run `nixos-anywhere` again**; this is a standard NixOS update.

If you have not copied in the automatic-credentials bundle, this guide alone does not activate credential transfer.

## 8. Verify the deployment

On the server, from an administrative shell:

```bash
systemctl status agentic-github-mcp.socket --no-pager
sudo stat -c '%a %U:%G %n' /etc/agentic/github-app/app.env /etc/agentic/github-app/private-key.pem
sudo journalctl -u agentic-github-mcp.service -n 60 --no-pager
```

Credential-file permissions should be `600 root:root`. Do not print the private key or dump the full service environment.

Then test **inside Pi** that the GitHub MCP tools are available and can read the selected repository. **A running socket alone does not prove Pi's MCP connection works.** Check the Pi MCP adapter and transport separately if tools are missing.

### Authentication architecture

```text
====================== BEGIN AGENTIC VPS ======================

	+------------- Pi / nono sandbox (uid agentic) ----------+
	| Pi: Git -> credential helper -> owner/repo request      |
	|     Git -> HTTPS push with returned token              |
	|     MCP client -> GitHub MCP socket                    |
	+--------------------------------------------------------+
	          | token request / response; MCP messages
	---------- nono / host process seam ----------------------

	HOST SYSTEMD (outside nono)
		+---------------------------+  +---------------------------+
		| Git credentials socket    |  | GitHub MCP socket         |
		| /run/agentic-git-         |  | /run/agentic-github-      |
		| credentials.sock (0600)   |  | mcp.sock (0600)           |
		+-------------+-------------+  +-------------+-------------+
		              | Accept=true                 | Accept=true
		              | one instance per connection | same
		+-------------v-------------+  +-------------v-------------+
		| agentic-git-credentials@0 |  | agentic-github-mcp@0      |
		| broker: one request       |  | stdio; PR/issue tools     |
		+---------------------------+  +---------------------------+
		+---------------------------+  +---------------------------+
		| agentic-git-credentials@1 |  | agentic-github-mcp@1      |
		| another connection        |  | another connection        |
		+---------------------------+  +---------------------------+

		+------------------ credentials ------------------------+
		| root-owned App PEM -> systemd LoadCredential ->      |
		| service instances only; PEM never enters nono       |
		| app.env: App ID; MCP uses one installation ID       |
		| Git broker: JWT -> lookup -> per-repo token          |
		+-------------------------------------------------------+

		+------------------ one-shot setup ---------------------+
		| agentic-configure-git-credentials.service           |
		| -> configure-git-credentials.sh -> ~/.gitconfig      |
		|    (registers helper and author; stores no token)   |
		+-------------------------------------------------------+

======================= END AGENTIC VPS =======================
	| Git HTTPS from Pi; GitHub API from broker/MCP instances
	v
+---------------------- GitHub (remote) -----------------------+
| App installation permissions + repo rulesets limit actions. |
+--------------------------------------------------------------+
```

Each `@` box is an instance of its corresponding `.service` template, created for one connection, not a separate GitHub App. The two columns are independent: Git receives a Contents-write token, while MCP uses its own App authentication for PRs and issues. The token crosses into nono for Git; the private key does not.

The per-connection broker instance keeps the root-owned PEM out of Pi's sandbox: Git's helper cannot run the signer directly without access to that key. One instance per request is a simple stateless choice, not a GitHub requirement; a long-running broker could instead handle connections and cache tokens. The socket's host permissions restrict who can connect, but **any process with socket access can request a Contents-write token** for any repository where this App is installed. The helper is not the socket's only possible caller. GitHub rulesets must protect branches; the broker does not enforce branch names. When pathname socket mediation is disabled in nono, `--allow-unix-socket` is not itself an enforced restriction.

Git pushes use a separate socket, `/run/agentic-git-credentials.sock`, and the `agentic-git-credential` helper configured for HTTPS `github.com` remotes. The helper sends the requested `owner/repository` to the broker. The broker signs a fresh JWT using its systemd-loaded PEM, discovers **this App's installation for that repository**, then requests an installation token restricted to that repository with Contents write. GitHub rejects requests for repositories without that App installation or sufficient permissions. Neither key nor token is stored by the broker. Code running as `agentic` can use a minted token while it remains valid; the socket also lets that user request tokens for any repository where the App is installed. Only GitHub HTTPS remotes are supported (not SSH or GitHub Enterprise). Multiple installations of the **same** App work; multiple different GitHub Apps and private keys at once do not. The existing MCP process still uses the single installation ID in `app.env` and may not have access to other installations. Do not print credentials with `git credential fill`, enable Git credential tracing, or put tokens in remote URLs.

Check the credential-helper service and socket from an administrative shell (do not print its credentials):

```bash
systemctl status agentic-git-credentials.socket agentic-configure-git-credentials.service --no-pager
git config --global --get-all credential.https://github.com.helper
```

The second command should be run as `agentic`; it prints only helper paths and the socket path, not tokens. The same one-shot service fills in missing `agentic` global `user.name` and `user.email` with `agentic-workbox[bot]` and `350248949+agentic-workbox[bot]@users.noreply.github.com`; it preserves each existing nonempty explicit value independently. It does not set identity for root or other users. Author attribution is independent of GitHub App authentication and grants no permissions. Applying unchanged helper and author settings leaves `~/.gitconfig` untouched, including its inode. When settings actually change, already-running Pi/nono sessions must restart to refresh their inode-bound file grant. Run `bash scripts/test-configure-git-credentials.sh` for credential-free checks of fresh provisioning, repeat apply, and an existing identity. Each checkout must use a GitHub HTTPS remote, and the App must be installed on that repository with Contents write permission. Verify inside `nnpi` that nono permits HTTPS to `github.com:443` (for example, `nono why --self --host github.com --port 443`); the token socket grant alone does not allow Git's network connection. Push a disposable `agentic/*` branch to confirm the complete path. If you push a workflow file, GitHub may require an additional Workflows permission; this App deliberately has none.

The official GitHub MCP server authenticates GitHub Apps in **`stdio` mode**, signs JWTs, and refreshes short-lived installation tokens itself. Its `http` mode does not provide the same built-in App-auth flow. Therefore the installed bridge must carry actual MCP messages between Pi and the stdio server, not merely expose a socket path.

Reference: [GitHub MCP — GitHub App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md).

## 9. Verify the real permissions

Run `bash github-protection/check.sh`. Resolve blocking failures before deployment; missing CI checks are warnings until CI is configured. With disposable branches and PRs, test using **the actual App credentials**: direct pushes to work branches, rejection of direct pushes to the default branch, rejection of merges into the default branch without approval, and a successful reviewed merge with passing checks. Push a new commit after approval and confirm old approval no longer authorizes a merge. Test any additional protected targets separately. Check that the App cannot bypass rulesets. Do not run destructive tests against production PRs. Record HTTP outcomes and any tests you could not perform. These tests alone cannot prove reviewer identity enforcement by rulesets.

**Deployment blocker:** this repository does not ship a trusted merge or label-scoped issue mutation service. Native rulesets cannot enforce the *identity* of the approver. Until a separate service is built, agents must not have an unrestricted App PR-write or Issues-write route (including MCP, raw API tokens, or another installation). A merge service must read the PR base and current head, check benjaminpreiss's non-dismissed approval on that head and required checks, then merge with the expected head SHA; it must verify the base is still the intended target immediately before the merge. For work-branch targets, it may omit the owner-approval check, not the checks/head validation. Give the service its own narrowly accessible write credential; do not expose it via the Git token socket. Similarly, Issues write is repository-wide: if label-scoped close/move is required, route *each mutation* through a service which rechecks the `agentic` label and issue identity before writing, with no alternate Issues-write route. This work is **not implemented** here; no claim of enforcement is made by this audit or by the official MCP server.

## 10. Daily workflow

```bash
ssh windcloud-vps-xl-ic3ht09rza
cd ~/work
nnpi
```

From a checkout with a GitHub HTTPS `origin` where this App is installed, start from the appropriate base branch, create a work branch, commit locally, and run `git push -u origin HEAD`. The Git credential helper supplies a fresh token scoped to that repository; no manual token export is needed. For this repo, open a PR into the default branch for review; PRs into other targets are optional. An approval count does not enforce reviewer identity. Neither the helper nor the broker limits which branch you push: configure GitHub rulesets for protected branches in **each** installed repository.

Example agent instruction:

> Create a work branch, implement and test the change, then open a PR into the default branch for approval and required checks. Work branches can be pushed directly; never push directly to the default branch. If a named reviewer is required, use a trusted merge gate; a ruleset approval count alone does not enforce identity.

Humans review PRs into the default branch; other branches are directly writable work branches.

## Official references

- [GitHub MCP server](https://github.com/github/github-mcp-server)
- [GitHub App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md)
- [GitHub App registration parameters](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters)
- [GitHub ruleset creation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [GitHub ruleset availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
