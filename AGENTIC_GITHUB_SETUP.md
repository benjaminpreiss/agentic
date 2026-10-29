# Agentic Workbox — GitHub App and branch safety setup

This guide configures a GitHub App for a coding agent running inside `nnpi` (Pi + nono) on the `agentic` server. The goal is to let agents create feature branches, raise pull requests (PRs), and merge successful PRs into `agentic`, while keeping `main` under human control.

> **Important:** Creating a GitHub App and GitHub rulesets does **not** configure authentication inside `nnpi`. A constrained credential broker still needs to be implemented and deployed. Until then, Pi cannot automatically authenticate using the App. GitHub App permissions apply repository-wide, **not per branch**.

## 1. Understand the workflow

```text
agent/fix-one ─┐
agent/feature ─┼── PRs + passing CI ──> agentic ── human-reviewed PR ──> main
agent/tests ──┘     agent may merge                         human merges
```

**Agent may:** read the repository, create `agent/*` branches, push commits to those branches, open PRs targeting `agentic`, inspect CI, and merge eligible PRs into `agentic`.

**Agent must not:** push to `main`, open or merge PRs targeting `main`, push directly to `agentic`, change repository settings, or access secrets. A broker policy will be needed to enforce the no-PR-to-main constraint.

## 2. Create or update the GitHub App

If you **have not created** the App, open this [pre-filled GitHub App registration link](https://github.com/settings/apps/new?name=agentic-workbox&description=Sandboxed%20coding%20agents%20with%20autonomous%20PRs%20into%20agentic%20and%20human-controlled%20main&url=https%3A%2F%2Fgithub.com%2Fbenjaminpreiss%2Fagentic&public=false&webhook_active=false&request_oauth_on_install=false&contents=write&pull_requests=write&issues=write&actions=read&checks=read&statuses=read).

If `agentic-workbox` **already exists**, go to https://github.com/settings/apps, select it, and manually update **Permissions & events**. The registration URL creates a *new* App; it does not update an existing one.

| Repository permission | Level | Why |
|---|---|---|
| Contents | Read & write | Read code, create commits, and push branches |
| Pull requests | Read & write | Create, update, and merge PRs |
| Issues | Read & write | Read, create, comment on, and triage issues |
| Actions | Read-only | Inspect workflow runs and job logs |
| Checks | Read-only | Inspect CI check runs and results |
| Commit statuses | Read-only | Read commit status contexts |
| Metadata | Read-only (required automatically) | Discover repositories and metadata |
| Workflows | No access | Do not give the agent permission to edit GitHub Actions workflow files |
| Administration, Secrets, Environments, Webhooks | No access | Avoid administrative and secret-management capabilities |
| All other permissions | No access initially | Add only for a concrete use case |

Leave **Webhooks disabled** and **OAuth on installation disabled** for this initial server-side integration. Choose a private App unless you deliberately need a public installation flow.

**Caution:** With Contents write access, the App can write broadly where GitHub branch protection does not restrict it. Do not treat the permission list as a branch-level boundary.

## 3. Install the App on selected repositories

1. Open your App settings and select **Install App**.
2. Choose your GitHub user/account.
3. Choose **Only select repositories**.
4. Initially select just `benjaminpreiss/agentic` (or another test repository).
5. Confirm installation. You can add more repositories later.

Keep the App’s installation scope narrow; access to all repositories is unnecessary.

## 4. Create the `agentic` integration branch

From a trusted workstation with Git access:

```bash
git clone git@github.com:benjaminpreiss/agentic.git
cd agentic
git switch main
git pull --ff-only
git switch -c agentic
git push -u origin agentic
```

If `agentic` already exists, do not recreate it. Use the GitHub **Branches** page to confirm `main` and `agentic` both exist.

## 5. Protect `main` with a strict ruleset

Open your repository on GitHub, then **Settings → Rules → Rulesets → New branch ruleset**. See the [GitHub ruleset documentation](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository).

- Name: `Protect main — human review`
- Enforcement: **Active** (not Evaluate or Disabled)
- Target branches: **main** only
- Require a pull request before merging: **On**
- Required approvals: **1 or more** from a trusted human reviewer
- Require status checks to pass: **On**, after you have a reliable CI check to select
- Block force pushes: **On**
- Restrict deletions: **On**
- Do **not** add `agentic-workbox` to any bypass list

If your GitHub plan and repository type support actor restrictions, consider **Restrict updates** with a carefully selected human bypass policy. **Test this carefully:** a restrict-updates rule can also block normal PR merges for actors who are not allowed to update the target branch. The ruleset needs to leave a legitimate path for human merges while rejecting App merges.

GitHub's approval count alone does not literally mean “humans only.” Verify that the App cannot satisfy approval/bypass conditions, and that agent-controlled accounts aren't given bypass rights.

**Plan caveat:** GitHub ruleset availability and enforcement differ by GitHub plan and whether repositories are public or private. Review GitHub's [ruleset availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets) before relying on this as a security boundary.

## 6. Protect `agentic` while allowing agent merges

Create a second branch ruleset:

- Name: `Agentic integration — PR + CI`
- Enforcement: **Active**
- Target branches: **agentic** only
- Require a pull request before merging: **On**
- Required approvals: **0** (allow autonomous merging)
- Require status checks to pass: **On** (select the checks your project actually runs)
- Block force pushes and restrict deletions: **On**
- Do not grant the App a full bypass that lets it skip the PR or checks requirements

Do **not** enable a “Restrict updates” rule here unless you specifically understand how its bypass list impacts PR merges. GitHub normally updates the base branch when a PR is merged; a restrictive actor rule could unintentionally prevent the App from merging.

Set suitable merge methods (squash merge is a practical default). `agentic` should remain an integration branch, not the repository's default branch unless you explicitly want that.

## 7. Design the credential broker before exposing GitHub access to Pi

GitHub Apps authenticate using a **private key** to sign an App JWT, then request short-lived **installation access tokens**. Your nono sandbox should not be able to read the private key.

Proposed server layout:

```text
/etc/agentic/github-app/private-key.pem  # root-only
/etc/agentic/github-app/app.env          # App/installation IDs
/run/agentic-github/broker.sock          # authenticated local request endpoint
/usr/local/bin/agentic-gh                # restricted agent-facing CLI
```

The broker should run outside nono and perform **specific operations** rather than give the agent an unrestricted GitHub token. Its policy should enforce:

| Operation | Policy |
|---|---|
| Clone/read an installed repository | Allow |
| Create/push an `agent/*` feature branch | Allow |
| Open a PR with base `agentic` | Allow |
| Merge an eligible PR with base `agentic` | Allow, once required CI is green |
| Direct push to `agentic` | Deny |
| Push to `main` | Deny |
| Open, retarget, or merge PRs into `main` | Deny |
| Force-push, delete protected branches, administer repo | Deny |
| Return a raw installation access token | Deny |

**Do not expose an unfiltered GitHub token as `GH_TOKEN` to Pi** if you need this guarantee: the token could be used against APIs or Git endpoints outside your intended branch policy. Also guard against indirect paths (e.g., PR retargeting, alternate API endpoints, Git push refspecs, and race conditions between checking a PR and merging it).

**Status:** This broker is a proposed component, **not yet part of `nnpi.sh`**. Building and testing it is required before the end-to-end agent workflow can work as described.

## 8. Keep your credentials out of the sandbox

In your GitHub App's General settings:

1. Record the **App ID**.
2. Install the App and record the **Installation ID**.
3. Generate and download a `.pem` private key.
4. Keep the key private, preferably first on your trusted workstation.
5. Never commit the key, put it in `~/work`, or paste it into Pi or chat.

When implementing the broker, install the key in a root-owned directory with restricted permissions, and use a systemd service with narrowly scoped filesystem and socket access. Non-root local access to its socket must be deliberately authorized; root-only file permissions alone do not make the broker safe.

## 9. Test the actual security boundaries

Before giving the agent any valuable repository access:

- [ ] App is installed on **only** intended repositories.
- [ ] App can create and push `agent/test-branch`.
- [ ] App can open a PR from that branch into `agentic`.
- [ ] App can merge the PR to `agentic` **only after** required CI checks pass.
- [ ] App cannot push directly to `agentic`.
- [ ] App cannot push or merge into `main`.
- [ ] Broker refuses PR creation or retargeting to `main`.
- [ ] Agent cannot read the `.pem` key or request a raw broad-access token.
- [ ] Human can still merge a reviewed PR from `agentic` into `main`.
- [ ] Agent cannot modify repository settings or GitHub Actions workflows.

If a negative test fails, do not treat `main` as protected until that path is fixed.

## 10. Daily workflow (after broker integration)

```bash
ssh windcloud-vps-xl-ic3ht09rza
cd ~/work
nnpi
```

Example agent request:

> Work on `benjaminpreiss/agentic`. Branch from `agentic` into `agent/fix-bootstrap`, implement and test the fix, open a PR targeting `agentic`, and merge once required CI checks pass. Do not modify `main`.

Periodically, a human reviews the accumulated changes in `agentic` and opens/merges a PR into `main`.

## Reference documentation

- [Register a GitHub App using URL parameters](https://docs.github.com/en/apps/sharing-github-apps/registering-a-github-app-using-url-parameters)
- [Creating rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/creating-rulesets-for-a-repository)
- [Available rules for rulesets](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/available-rules-for-rulesets)
- [About rulesets and plan availability](https://docs.github.com/en/repositories/configuring-branches-and-merges-in-your-repository/managing-rulesets/about-rulesets)
- [GitHub App token permissions](https://docs.github.com/en/rest/apps/apps)
