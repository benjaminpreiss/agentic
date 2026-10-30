# Agentic — GitHub App setup

This guide sets up **GitHub's official MCP server** for the NixOS coding VPS, with GitHub App credentials supplied from your Mac. Pi runs inside nono; the MCP server and its credentials run outside the sandbox.

**Goal:** agents work on `agent/*` branches, open and merge passing PRs into `agentic`, while humans review changes before merging into `main`.

> The older custom Go/Python GitHub API broker and `agentic-gh` CLI are **not part of this setup**. GitHub rulesets protect branches. The unfiltered official MCP server does not enforce your own PR-target or branch-prefix policy.

## 1. Create the GitHub App

**[Open the prefilled GitHub App registration form](https://github.com/settings/apps/new?name=agentic-workbox&description=Sandboxed%20coding%20agents%20with%20autonomous%20PRs%20into%20agentic%20and%20human-controlled%20main&url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=write&issues=write&actions=read&checks=read&statuses=read)**

Review the prefilled settings before submitting. If you already created the App, open [GitHub App settings](https://github.com/settings/apps) to edit the existing App instead; the registration link creates a **new** App.

Recommended repository permissions:

| Permission | Level | Purpose |
|---|---|---|
| Contents | Read & write | Read code, create commits, update branches |
| Pull requests | Read & write | Open and merge PRs |
| Issues | Read & write | Work with issues |
| Actions | Read-only | Inspect workflow runs |
| Checks | Read-only | Inspect CI results |
| Commit statuses | Read-only | Inspect statuses |
| Metadata | Read-only (automatic) | Required by GitHub |
| Workflows, Administration, Secrets, Environments | No access | Limit privileges |
| Others | No access initially | Add only if needed |

Choose a **private App**. Leave **webhooks disabled** and **OAuth on installation disabled** for this headless setup. GitHub App permissions are repository-scoped, not branch-scoped; enabling Contents write does **not** restrict the App to `agent/*`.

## 2. Install the App

1. In the App settings, click **Install App**.
2. Choose the GitHub account owning the repository.
3. Select **Only select repositories**.
4. Choose `benjaminpreiss/agentic` initially.
5. Complete installation.

On the App's **General** page, record the **App ID** and generate/download a **private key** (`.pem`). Also record the **installation ID** associated with the installation. Never paste the PEM into chat, Pi, or the repository.

## 3. Prepare the `agentic` branch

Confirm `main` and `agentic` are present on GitHub. If `agentic` is absent, create it from `main` in a trusted Git checkout on your Mac:

```bash
git switch main
git pull --ff-only
git switch -c agentic
git push -u origin agentic
```

Do **not** recreate the branch if it already exists.

```text
agent/fix-123 ── PR + passing CI ──> agentic ── reviewed PR + passing CI ──> main
agent/feature ── PR + passing CI ──> agentic
```

## 4. Audit branch protection for every installed repository

After completing credential setup in section 6, run this **read-only** audit on your Mac from the project root:

```bash
bash scripts/check-github-protection.sh
```

The Bash script requires `curl`, `jq`, `openssl`, `base64`, and standard macOS command-line utilities. It uses your GitHub App ID, installation ID and selected PEM from `secrets/github-app/`. It creates a short-lived installation token **in memory**, lists **every repository accessible to this App installation** (including paginated results), and checks the active GitHub branch rules for `main` and `agentic` in each repository. No permanent token is saved; no rulesets are changed.

It checks for required PRs, at least one required approval on `main`, configured CI checks, protection against force pushes, and protection against branch deletion. It reports missing branches, API errors and missing checks. An exit code of `0` means all *machine-checkable* requirements passed; a nonzero exit means attention is needed or the audit could not complete.

**IMPORTANT:** An audit is not a substitute for enforcement. The script **does not create rulesets**, cannot prove which human is reviewing, and cannot always inspect ruleset bypass actors with the App's restricted permissions. Even a passing audit is **not proof** the App is unable to bypass restrictions. Manually verify that this App has no bypass rights for `main`, and test that it cannot directly push or merge into `main` without approvals.

To fix missing protections: on GitHub, open the affected repository and navigate to **Settings → Rules → Rulesets → New branch ruleset**. Apply **Active** rulesets matching the audit's missing requirements. For `agentic`, use zero required approvals if agents should merge autonomously. Choose CI checks that actually exist. Re-run the audit after fixing them.

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

The official GitHub MCP server authenticates GitHub Apps in **`stdio` mode**, signs JWTs, and refreshes short-lived installation tokens itself. Its `http` mode does not provide the same built-in App-auth flow. Therefore the installed bridge must carry actual MCP messages between Pi and the stdio server, not merely expose a socket path.

Reference: [GitHub MCP — GitHub App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md).

## 9. Verify the real permissions

Run `bash scripts/check-github-protection.sh` and resolve any warnings. Then test on a disposable branch and PR that the App can work on `agent/*`, merge passing PRs into `agentic`, **cannot push directly to `main` or `agentic`**, and cannot merge into `main` without the required human review. Confirm the App has no `main` ruleset bypass privileges in GitHub Settings.

**Native rulesets cannot prevent an App with PR-write access from merely *opening* a PR targeting `main`.** The audit cannot change that limitation. The official MCP server also does not enforce a custom `agent/*` branch-prefix policy by itself.

## 10. Daily workflow

```bash
ssh windcloud-vps-xl-ic3ht09rza
cd ~/work
nnpi
```

Example agent instruction:

> Start from `agentic`, create an `agent/*` branch, implement and test the change, then open a PR targeting `agentic`. Merge only when required GitHub checks pass. Never push directly to `main` or `agentic`; never merge into `main`.

Humans periodically review `agentic` and promote changes to `main` via GitHub PRs.

## Official references

- [GitHub MCP server](https://github.com/github/github-mcp-server)
- [GitHub App authentication](https://github.com/github/github-mcp-server/blob/main/docs/github-app-auth.md)
- [GitHub App registration parameters](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters)
- [GitHub ruleset creation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [GitHub ruleset availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
