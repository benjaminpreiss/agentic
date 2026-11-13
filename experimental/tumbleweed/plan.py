#!/usr/bin/env python3
"""Prototype interface-aware planner. Generates Ansible; never changes the host."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IDENTIFIER = re.compile(r"[a-z][a-z0-9-]*\Z")


def plan(directory: Path):
    interfaces = {}
    for path in sorted((directory.parent / "interfaces").glob("*.json")):
        spec = json.loads(path.read_text())
        key = f'{spec["id"]}@{spec["version"]}'
        if not IDENTIFIER.fullmatch(spec["id"]) or path.name != f'{spec["id"]}.v{spec["version"]}.json':
            raise ValueError(f"invalid interface: {path}")
        if key in interfaces:
            raise ValueError(f"duplicate interface: {key}")
        interfaces[key] = spec
    bindings_path = directory.parent / "bindings.json"
    bindings = json.loads(bindings_path.read_text()) if bindings_path.exists() else {}
    modules = {}
    for path in sorted(directory.glob("*/module.json")):
        module = json.loads(path.read_text())
        key = module["id"]
        if not IDENTIFIER.fullmatch(key) or path.parent.name != key:
            raise ValueError(f"module ID must match directory: {path}")
        if not (path.parent / "introduce.yml").is_file():
            raise ValueError(f"missing introduction script: {path.parent}")
        if key in modules:
            raise ValueError(f"duplicate module {key}")
        if not all(isinstance(module.get(field), str) for field in ("id", "version", "substrate", "status")):
            raise ValueError(f"invalid module: {path}")
        if "requires" in module:
            raise ValueError(f"use required interfaces, not concrete module dependencies: {path}")
        if not isinstance(module.get("requires_interfaces"), list):
            raise ValueError(f"invalid interface dependencies: {path}")
        if not isinstance(module.get("implements"), str) or not isinstance(module.get("entrypoint"), str):
            raise ValueError(f"missing provided interface or entrypoint: {path}")
        modules[key] = module

    for key, provider_id in bindings.items():
        if key not in interfaces:
            raise ValueError(f"unknown interface: {key}")
        if provider_id not in modules:
            raise ValueError(f"missing provider: {provider_id}")
        operations = modules[provider_id].get("provides", {}).get(key)
        if not isinstance(operations, dict):
            raise ValueError(f"{provider_id} does not provide {key}")
        if set(operations) != set(interfaces[key]["operations"]):
            raise ValueError(f"{provider_id} does not implement all methods of {key}")
        if modules[provider_id]["implements"] != key:
            raise ValueError(f"{provider_id} does not implement its bound interface {key}")
        entrypoint = modules[provider_id]["entrypoint"]
        if entrypoint not in operations or interfaces[key]["operations"][entrypoint]["args"]:
            raise ValueError(f"{provider_id} needs a zero-argument entrypoint")
        for operation, filename in operations.items():
            if operation not in interfaces[key]["operations"] or not re.fullmatch(r"[a-z][a-z0-9-]*\.yml", filename):
                raise ValueError(f"invalid provider operation: {key}.{operation}")
            if not (directory / provider_id / filename).is_file():
                raise ValueError(f"missing provider script: {provider_id}/{filename}")

    for key, module in modules.items():
        if bindings.get(module["implements"]) != key:
            raise ValueError(f"unbound implementation: {key} -> {module['implements']}")
        required = module["requires_interfaces"]
        if not isinstance(required, list) or len(required) != len(set(required)):
            raise ValueError(f"invalid required interfaces: {key}")
        if module["substrate"] != "native" and module["substrate"] not in required:
            raise ValueError(f"substrate must be a required interface: {key}")
        dependencies = []
        for interface in required:
            if interface not in bindings:
                raise ValueError(f"unbound interface: {interface}")
            provider = bindings[interface]
            if provider == key:
                raise ValueError(f"module cannot depend on itself as provider: {key}")
            dependencies.append(provider)
        calls = []
        for call in module.get("calls", []):
            interface, operation, args = call["interface"], call["operation"], call["args"]
            if interface not in required:
                raise ValueError(f"undeclared interface dependency: {key} -> {interface}")
            spec = interfaces[interface]["operations"].get(operation)
            provider = bindings[interface]
            filename = modules[provider]["provides"][interface].get(operation)
            if spec is None or filename is None:
                raise ValueError(f"unsupported operation: {interface}.{operation}")
            expected = spec["args"]
            if any(arg_type != "string" for arg_type in expected.values()):
                raise ValueError(f"unsupported argument type: {interface}.{operation}")
            if set(args) != set(expected) or any(not isinstance(args[name], str) for name in expected):
                raise ValueError(f"signature mismatch: {key} calls {interface}.{operation}")
            calls.append((provider, filename, interface.split("@")[0], operation, args))
        module["_dependencies"] = dependencies
        module["_calls"] = calls

    ordered, visiting, visited = [], set(), set()
    def visit(key):
        if key not in modules:
            raise ValueError(f"missing dependency: {key}")
        if key in visiting:
            raise ValueError(f"dependency cycle at {key}")
        if key in visited:
            return
        visiting.add(key)
        for dep in modules[key]["_dependencies"]:
            visit(dep)
        visiting.remove(key)
        visited.add(key)
        ordered.append(modules[key])

    for key in modules:
        visit(key)
    return ordered


def playbook(ordered):
    lines = ["---", "- name: Prototype Agentic Tumbleweed introductions", "  hosts: agentic_vm", "  gather_facts: true", "  become: true", "  tasks:"]
    for module in ordered:
        entrypoint_file = module["provides"][module["implements"]][module["entrypoint"]]
        lines += [f"    - name: {module['id']} implements {module['implements']}.{module['entrypoint']}",
                  f"      ansible.builtin.import_tasks: modules/{module['id']}/{entrypoint_file}"]
        for provider, filename, interface, operation, args in module["_calls"]:
            lines += [f"    - name: {module['id']} calls {interface}.{operation}",
                      f"      ansible.builtin.include_tasks: modules/{provider}/{filename}",
                      "      vars:"]
            for name, value in args.items():
                lines.append(f"        {interface}_{name}: {json.dumps(value)}")
    return "\n".join(lines) + "\n"


def closure(ordered, target):
    lookup = {module["id"]: module for module in ordered}
    if target not in lookup:
        raise ValueError(f"unknown target module: {target}")
    required = set()
    def visit(key):
        if key in required:
            return
        required.add(key)
        for dep in lookup[key]["_dependencies"]:
            visit(dep)
    visit(target)
    return [module for module in ordered if module["id"] in required]


if __name__ == "__main__":
    try:
        ordered = plan(ROOT / "modules")
        if len(sys.argv) == 1:
            for module in ordered:
                print(f'{module["id"]}@{module["version"]} [{module["substrate"]}] {module["status"]}')
        elif sys.argv[1:] == ["--playbook"]:
            print(playbook(ordered), end="")
        elif len(sys.argv) == 3 and sys.argv[1] == "--until":
            print(playbook(closure(ordered, sys.argv[2])), end="")
        else:
            raise ValueError("usage: plan.py [--playbook | --until MODULE_ID]")
    except (ValueError, OSError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
