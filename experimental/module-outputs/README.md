# Experiment: outputs across module interfaces

**Independent draft experiment**, not an Agentic installer and not a replacement for the NixOS deployment or Tumbleweed prototype in PRs #36/#38. Use only on a freshly installed, disposable openSUSE Tumbleweed VM with tested out-of-band console access. Running the generated Ansible playbook installs Zsh and may create the `agentic` account. It does not configure networking, SSH, a sandbox, or any agent harness.

## Question

Can a module require a result from another module without knowing its implementation or embedding its configuration? The real test here is `Zsh → verified path → agentic account`, not whether JSON can describe an edge in a graph.

```text
bindings.json: login-shell@1#interactive → zsh

zsh/module.json:
  provides login-shell@1.ensure() → {path: string}
zsh/ensure.yml:
  installs Zsh, resolves the target's executable, verifies it is executable
  and listed in /etc/shells; publishes a value for the bound instance

agentic-account/module.json:
  requires login-shell@1#interactive.ensure() → {path: string}
  inputs.shell_path ← that instance's ensure.path
agentic-account/ensure.yml:
  creates agentic with shell_path and checks passwd and group membership
```

Each `module.json` describes its *own* provided methods and the signatures it expects of its required methods. `bindings.json` chooses provider instances; it does not define interfaces. `plan.py` checks signatures, output references, binding identities and graph cycles, then generates an Ansible playbook. The playbook clears previous run results, invokes providers first, checks reported output types, and passes the path as an input variable to the account module. The provider checks the actual path, not merely its declared type. The account module refuses to change an existing account to a different shell without an explicit migration.

## Trying it

From the repository root, `python3 experimental/module-outputs/plan.py` displays order and `python3 -m unittest discover -s experimental/module-outputs -p 'test_*.py'` checks the planner. For a **disposable VM only**:

```bash
cd experimental/module-outputs
python3 plan.py --playbook > introduction.generated.yml
ansible-playbook -i /private/path/to/inventory.ini introduction.generated.yml \
  -e agentic_disposable_vm=true -e agentic_console_verified=true
```

Only set those confirmations after checking the actual target. `introduction.generated.yml` and local inventory are ignored by Git. Run the playbook a second time and check the user and shell through `getent passwd agentic`; an unchanged result is the expected postcondition. Ansible is not installed in this development environment, so the playbook has **not** passed Ansible syntax validation or a Tumbleweed VM run yet.

## What this experiment does **not** establish

- The prototype holds outputs in **one Ansible play**, not a durable state store. Drift, upgrades, removal and interrupted operations still need a model.
- One binding selects one provider for one instance. Rebinding a live account is a migration, not a transparent substitution.
- Contract checking covers method names and string input/output types. It cannot prove that a provider truly installed a safe login shell; the provider's checks and VM tests must establish that.
- Ansible is an implementation behind the module interface, not a required part of that interface. If result propagation or recovery proves awkward on a VM, that is evidence for changing the execution model—not a reason to build a custom runner before testing it.
