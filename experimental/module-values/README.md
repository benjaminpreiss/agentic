# Experiment: static values and effectful deployment transitions

**Independent draft experiment**, not an Agentic installer and not a replacement for the NixOS deployment or Tumbleweed prototype in PRs #36/#38. Use only on a freshly installed, disposable openSUSE Tumbleweed VM with tested out-of-band console access. The generated Ansible playbook installs Zsh and may create the `agentic` account. It does not configure networking, SSH, a sandbox or agent harnesses.

## Two different phases

1. **Template expansion (pure, before contacting a target):** `python3 plan.py --expand` loads versioned interfaces, module implementations and instance configurations. It resolves `interactive.path` from the Zsh module declaration to `/usr/bin/zsh` and substitutes it into the `agentic` account instance. The expanded JSON retains where the value came from; it contains **no** Ansible commands or runtime observations.
2. **Deployment execution (effectful, on a target):** `python3 plan.py --playbook` renders the expanded data into Ansible tasks. `zsh.ensure` installs Zsh and verifies that the **declared** path exists, is executable and is registered in `/etc/shells`. `account.ensure` configures and verifies the account with that same path. It refuses to silently change an existing account to a different shell. The plan cannot claim those checks passed before execution.

These are separate kinds of interface surface: `login-shell@1.values.path` is a deterministic, typed *static value*; `login-shell@1.transitions.ensure` is an effectful transition. There is no `command -v zsh` discovery or Ansible result substitution. If `/usr/bin/zsh` is wrong on a target, deployment fails its check rather than quietly changing the account declaration. A different Zsh layout requires a different provider declaration/version or an explicitly parameterised instance.

```text
interfaces/opensuse-tumbleweed.v1.json  explicit host contract for this OS
interfaces/login-shell.v1.json          portable shell contract and static path type
modules/zsh-on-tumbleweed/              implements login-shell@1; path=/usr/bin/zsh
modules/tumbleweed-local-account/       implements account@1; uses login-shell@1.path
instances/interactive.json             binds opensuse-tumbleweed@1 to host
instances/agentic.json                 name=agentic; binds login-shell@1 to interactive
```

**Modules** map transitions to scripts, declare static values, required interfaces and where static values are used. Both the Zsh implementation and the reusable local-account implementation explicitly require `opensuse-tumbleweed@1`: installing `zsh`, reading `/etc/shells`, and using `getent` are not promises of an abstract Linux base. This avoids adding a shallow package-manager wrapper over Ansible's existing package abstraction. A second OS implementation can reveal which narrower cross-distribution contracts are genuinely shared. **Instances** have stable identity, literal configuration and provider-instance bindings. The account module contains neither `agentic` nor `/bin/zsh`. A second account instance can reuse the same account module and shell provider; `test_plan.py` exercises this case. These interface files live in this experiment, **not in the framework**; independent publication is still an open packaging question.

## Trying it

From the repository root, run:

```bash
python3 experimental/module-values/plan.py --expand
python3 -m unittest discover -s experimental/module-values -p 'test_*.py'
```

To run **only on a disposable VM** with a verified console:

```bash
cd experimental/module-values
python3 plan.py --playbook > introduction.generated.yml
ansible-playbook -i /private/path/to/inventory.ini introduction.generated.yml \
  -e agentic_disposable_vm=true -e agentic_console_verified=true
```

Only set those confirmations after checking the target. `introduction.generated.yml` and local inventory are ignored by Git. Run it again and check `getent passwd agentic`; an unchanged account is the expected postcondition. Ansible is not installed in this development environment, so the playbook has **not** passed Ansible syntax validation or a Tumbleweed VM run yet.

## Not established

- Static values can change when module versions or configuration change; replacing a provider or changing a live account's name needs an explicit migration. This prototype has no prior-state record and **must not** be used for either change.
- The planner type-checks static values but cannot prove the interfaces' written guarantees. Target-side checks and a real VM rerun are required.
- Runtime observations, drift, interrupted transitions, removal, secrets and password management are out of scope. Do not put secrets in instance JSON or generated playbooks.
- Ansible remains one possible deployment executor. This experiment does not justify building a custom one yet.
