# Experiment: reusable modules, configured instances and verified outputs

**Independent draft experiment**, not an Agentic installer and not a replacement for the NixOS deployment or Tumbleweed prototype in PRs #36/#38. Use only on a freshly installed, disposable openSUSE Tumbleweed VM with tested out-of-band console access. Running the generated Ansible playbook installs Zsh and may create the `agentic` account. It does not configure networking, SSH, a sandbox or agent harnesses.

## The model being tested

```text
interfaces/os-base.v1.json               declares os-base@1.ensure()
interfaces/login-shell.v1.json            declares login-shell@1.ensure() -> path
interfaces/account.v1.json                declares account@1.ensure()
modules/opensuse-tumbleweed/module.json   implements os-base@1
modules/zsh/module.json                   implements login-shell@1; requires os-base@1
modules/linux-local-account/module.json   implements account@1; requires login-shell@1

instances/host.json          uses opensuse-tumbleweed
instances/interactive.json   uses zsh; binds os-base@1 to host
instances/agentic.json       uses linux-local-account; binds login-shell@1 to interactive;
                             configures account_name=agentic
```

**Interfaces** are separate versioned contracts with canonical method arguments, outputs and written guarantees. They live in this experiment's `interfaces/` directory, not in the framework; they could be independently authored packages later. **Modules** select an interface to implement, map its methods to scripts, name required interfaces and declare input sources. No signature is copied into provider or consumer module JSON. **Instances** select a module, hold stable identity and configuration, and bind their required interfaces to specific provider instances. The account module contains neither `agentic` nor `/bin/zsh`: its account name comes from the instance configuration, and its shell path comes from the Zsh instance's verified output. A second account instance can reuse the same account module and shell provider; `test_plan.py` exercises this case.

`plan.py` validates shared interface definitions, requires a provider to implement every method of its interface, checks instance bindings and output references, rejects cycles, and emits an Ansible playbook. The playbook clears previous-run results, introduces providers before consumers, checks reported output types and injects inputs into the account module. Zsh verifies the executable on the target and checks `/etc/shells`; the local-account module uses `getent` to verify the resulting passwd record, refuses to change an existing account to a different shell without a migration, and rejects administrator groups. Its scope is **unprivileged local login accounts**, not every possible Linux account. Ansible remains a private execution backend, not part of the module interface.

## Trying it

From the repository root, run `python3 experimental/module-outputs/plan.py` to see instance order and `python3 -m unittest discover -s experimental/module-outputs -p 'test_*.py'` to test contract validation and reuse. For a **disposable VM only**:

```bash
cd experimental/module-outputs
python3 plan.py --playbook > introduction.generated.yml
ansible-playbook -i /private/path/to/inventory.ini introduction.generated.yml \
  -e agentic_disposable_vm=true -e agentic_console_verified=true
```

Only set those confirmations after checking the actual target. `introduction.generated.yml` and local inventory are ignored by Git. Run it a second time and check `getent passwd agentic`; an unchanged result is the expected postcondition. Ansible is not installed in this development environment, so the playbook has **not** passed Ansible syntax validation or a Tumbleweed VM run yet.

## What this does not establish

- Outputs exist only within **one Ansible play**, not in a durable state store. Drift, upgrades, removal and interrupted operations need a model.
- A binding selects a provider **instance**. Rebinding a live account or changing its configured name requires an explicit migration; this prototype cannot detect prior bindings or names and must **not** be used for either change. Signature compatibility alone does not make it safe.
- The contract's written guarantees say more than its string input/output types, but the planner cannot prove those guarantees; the provider's checks and a VM rerun must establish them.
- Secrets and password management are deliberately out of scope; do not place secrets in instance JSON or generated Ansible playbooks.
