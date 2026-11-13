#!/usr/bin/env python3
"""Prototype dependency planner and Ansible playbook generator. No host changes."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def plan(directory: Path):
    modules = {}
    for path in sorted(directory.glob("*/module.json")):
        module = json.loads(path.read_text())
        key = module["id"]
        if not re.fullmatch(r"[a-z][a-z0-9-]*", key) or path.parent.name != key:
            raise ValueError(f"module ID must match directory: {path}")
        if not (path.parent / "introduce.yml").is_file():
            raise ValueError(f"missing introduction script: {path.parent}")
        if key in modules:
            raise ValueError(f"duplicate module {key}")
        if not all(isinstance(module.get(field), str) for field in ("id", "version", "substrate", "status")):
            raise ValueError(f"invalid module: {path}")
        if not isinstance(module.get("requires"), list):
            raise ValueError(f"invalid dependencies: {path}")
        modules[key] = module

    ordered = []
    visiting = set()
    visited = set()

    def visit(key):
        if key not in modules:
            raise ValueError(f"missing dependency: {key}")
        if key in visiting:
            raise ValueError(f"dependency cycle at {key}")
        if key in visited:
            return
        visiting.add(key)
        for dep in modules[key]["requires"]:
            visit(dep)
        visiting.remove(key)
        visited.add(key)
        ordered.append(modules[key])

    for key in modules:
        visit(key)
    return ordered


def playbook(ordered):
    """Static imports make the planned ordering inspectable before running Ansible."""
    lines = ["---", "- name: Prototype Agentic Tumbleweed introductions", "  hosts: agentic_vm", "  gather_facts: true", "  become: true", "  tasks:"]
    for module in ordered:
        lines += [f"    - name: Introduce {module['id']}",
                  f"      ansible.builtin.import_tasks: modules/{module['id']}/introduce.yml"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        ordered = plan(ROOT / "modules")
        if len(sys.argv) == 1:
            for module in ordered:
                print(f'{module["id"]}@{module["version"]} [{module["substrate"]}] {module["status"]}')
        elif sys.argv[1:] == ["--playbook"]:
            print(playbook(ordered), end="")
        elif len(sys.argv) == 3 and sys.argv[1] == "--until":
            target = sys.argv[2]
            if target not in [module["id"] for module in ordered]:
                raise ValueError(f"unknown target module: {target}")
            # Limit to the target's dependency closure, not just a prefix of
            # the globally ordered list (unrelated modules can occur earlier).
            lookup = {module["id"]: module for module in ordered}
            required = set()
            def add_dependencies(key):
                required.add(key)
                for dep in lookup[key]["requires"]:
                    add_dependencies(dep)
            add_dependencies(target)
            print(playbook([module for module in ordered if module["id"] in required]), end="")
        else:
            raise ValueError("usage: plan.py [--playbook | --until MODULE_ID]")
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
