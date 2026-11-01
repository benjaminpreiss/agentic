# Set up GitHub access for the NixOS agent

This guide connects sandboxed Pi to GitHub through two host-side processes: the official GitHub MCP server for issues and PRs, and a Git credential broker for HTTPS pushes. Both use one GitHub App. **The App private key stays outside Pi's sandbox and the Nix store.**

The intended workflow is `agent/*` branch → PR into `agentic` → human-reviewed PR into `main`. GitHub rulesets, **not** the agent or its credential helper, must enforce the protected branches.

## Before you start

You need an installed, SSH-reachable Agentic NixOS machine, its working `.deployment/` directory on your deployment computer, and access to GitHub App settings and repository rulesets. Follow [the update guide](docs/APPLY-EXISTING-NIXOS.md) for the non-destructive deployment path. **Do not rerun the fresh installer** to add GitHub access.

The steps below use `benjaminpreiss/agentic` as the first repository. One App can be installed in more repositories and across multiple installations; the MCP server uses the installation ID you configure, while the Git broker looks up the installation for each requested repository. Multiple *different* Apps are not supported at once.

## 1. Create and install a private GitHub App

[Open the prefilled App registration form](https://github.com/settings/apps/new?name=agentic-workbox&description=Sandboxed%20coding%20agents%20with%20autonomous%20PRs%20into%20agentic%20and%20human-controlled%20main&url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=write&issues=write&actions=read&checks=read&statuses=read), or edit an existing App in [App settings](https://github.com/settings/apps). Review the form before submitting: use a **private App**, with webhooks and OAuth on installation disabled.

| Repository permission | Level | Why |
| --- | --- | --- |
| Contents, pull requests, issues | Read & write | Push code, open/merge PRs, work on issues |
| Actions, checks, commit statuses | Read-only | Inspect CI |
| Metadata | Read-only (automatic) | Required by GitHub |
| Workflows, administration, secrets, environments | No access | Avoid unnecessary privilege |

Install the App on **Only select repositories**, starting with `benjaminpreiss/agentic`. On its General page, record the **App ID**, download a private key (`.pem`), and record the **installation ID**. Do not paste the PEM into chat or commit it.

App permissions apply to whole repositories, **not** only to `agent/*` branches. Create active GitHub rulesets for `main` and `agentic` under **Settings → Rules → Rulesets** before giving an agent write access:

- Require PRs, prevent force pushes and deletion, and permit only **squash** merging on each branch.
- Require at least one human approval on `main`. If agents should merge into `agentic` on their own, set its required approvals to zero.
- Select required CI checks once workflows exist. Make sure the App has **no bypass permission** on `main`.

If `agentic` does not exist yet, create it from `main` in a trusted local checkout:

```bash
git switch main
git pull --ff-only
git switch -c agentic
git push -u origin agentic
```

Do not recreate an existing branch. Rulesets cannot prevent this App from merely *opening* a PR targeting `main`; human review and branch protection control merging.

## 2. Store credentials on your deployment computer

Keep the downloaded PEM under `secrets/github-app/`, outside `.deployment/`. For example, from this repository's root:

```bash
mkdir -p secrets/github-app
mv ~/Downloads/YOUR-GITHUB-APP-KEY.pem secrets/github-app/
chmod 600 secrets/github-app/YOUR-GITHUB-APP-KEY.pem
ln -sfn YOUR-GITHUB-APP-KEY.pem secrets/github-app/private-key.pem
bash scripts/configure-github-app.sh
```

Replace the example filename with the actual download. The script asks for the App ID and installation ID and writes `secrets/github-app/app.env`. The `private-key.pem` link selects the active key and **must point to a PEM in the same directory**. To rotate keys, put the new PEM there, change the link, and rerun `scripts/apply.sh`.

**Never put keys or tokens in `.deployment/`, Nix expressions, Git history, or a published archive.** Both `secrets/` and `.deployment/` are ignored by Git; still inspect what you stage before committing. The deployment uploads credentials separately from the Nix flake source.

## 3. Check branch rules, then apply

Run the read-only audit on your deployment computer:

```bash
bash scripts/check-github-protection.sh
```

It needs `curl`, `jq`, `openssl`, `base64`, and the credentials above. It checks `main` and `agentic` in **every repository accessible to the configured installation**, not in other installations. It reports ✅ passes, ⚠️ warnings, and ❌ blocking failures; a nonzero exit status means a blocking finding. It checks required PRs, squash-only merge rules, at least one approval on `main`, and protection against force pushes and deletion. For CI it compares required status checks with contexts observed on each branch's *current tip*: `0/0` or `1/2` is a warning, not proof that CI is safe or unsafe. Checks that only run on PRs may not appear there.

Fix blocking findings in GitHub rulesets and rerun the audit. A passing audit **does not create rulesets or prove that the App lacks bypass rights**; inspect bypass permissions manually and later test an actual push and PR. Protect any additional installation's repositories separately.

Once the branch rules are ready, update the existing NixOS machine:

```bash
bash scripts/apply.sh
```

`apply.sh` evaluates and switches NixOS without repartitioning. When local App credentials are present, it uploads them over SSH as root-owned files at `/etc/agentic/github-app/{app.env,private-key.pem}`, separate from the flake source. It also prepares and verifies the nono profiles. Do not print the PEM or the full service environment.

## 4. Verify on the server

From an administrative shell, check the sockets and the credential-file permissions:

```bash
systemctl status agentic-github-mcp.socket agentic-git-credentials.socket --no-pager
sudo stat -c '%a %U:%G %n' /etc/agentic/github-app/app.env /etc/agentic/github-app/private-key.pem
```

Both files should report `600 root:root`. As `agentic`, check that Git has a helper configured for GitHub without requesting or printing a token:

```bash
git config --global --get-all credential.https://github.com.helper
```

Start `pi` from `~/work` and test that GitHub MCP tools can **read the selected repository**. A listening socket by itself does not establish that Pi can use MCP. Next, from a checkout using a GitHub **HTTPS** remote, push a disposable `agent/*` branch and open a PR to `agentic`. Confirm that the App cannot push directly to `main` or `agentic`, or merge into `main` without the required review. The token socket alone does not permit Git's HTTPS connection; if Git cannot reach GitHub, check nono's network decision from inside the sandbox (for example, `nono why --self --host github.com --port 443`).

## What the setup does—and does not—protect

```text
Pi (inside nono) ── MCP socket ──> host MCP server ──> GitHub issues and PRs
Pi's Git helper   ── token socket ──> host broker ──> GitHub repo-scoped token
                                        ↑
                              root-owned App private key
```

Systemd owns both sockets; each connection starts a separate host-side process. Systemd passes the private key to those processes, **never to Pi**. Git receives a short-lived, repository-scoped Contents-write token; the MCP server authenticates separately using the configured installation ID. Neither the broker nor the helper restricts Git branch names. Only GitHub HTTPS remotes are supported, not SSH or GitHub Enterprise. Pushing workflow files may require Workflows permission, which this setup deliberately omits.

**A socket is a powerful capability.** Any process able to reach the Git token socket can request a token for a repository where the App is installed; code running as `agentic` can use that token while it is valid. When nono pathname-socket mediation is disabled, a `--allow-unix-socket` flag alone is not an enforced restriction. Do not print tokens with `git credential fill`, enable credential tracing, or embed tokens in remote URLs. The official MCP server uses `stdio` mode for GitHub App authentication; its `http` mode does not provide the same built-in flow.

## Day-to-day use

```bash
ssh YOUR_SERVER
cd ~/work
pi
```

From a GitHub HTTPS checkout, create an `agent/*` work branch, push it, and open a PR into `agentic`. Required checks and GitHub rulesets govern merging. Humans promote reviewed changes from `agentic` to `main` through a separate PR. Apply protections in **every** repository where the App is installed.

Further reading: [GitHub MCP server](https://github.com/github/github-mcp-server), [App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md), [rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository), [active branch rules](https://docs.github.com/en/rest/repos/rules#get-rules-for-a-branch).
