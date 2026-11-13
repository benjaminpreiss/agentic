#!/usr/bin/env python3
"""Bind consumer-owned requirements to provider-owned contracts; emit Ansible."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
IDENTIFIER = re.compile(r"[a-z][a-z0-9-]*\Z")
INTERFACE = re.compile(r"[a-z][a-z0-9-]*@[1-9][0-9]*\Z")
SCRIPT = re.compile(r"[a-z][a-z0-9-]*\.yml\Z")


def plan(directory: Path):
    bindings_path = directory.parent / "bindings.json"
    bindings = json.loads(bindings_path.read_text()) if bindings_path.exists() else {}
    modules = {}
    for path in sorted(directory.glob("*/module.json")):
        module = json.loads(path.read_text())
        key = module["id"]
        if not IDENTIFIER.fullmatch(key) or path.parent.name != key:
            raise ValueError(f"module ID must match directory: {path}")
        if key in modules:
            raise ValueError(f"duplicate module {key}")
        if not all(isinstance(module.get(field), str) for field in ("id", "version", "substrate", "status")):
            raise ValueError(f"invalid module: {path}")
        if "requires" in module:
            raise ValueError(f"use required interfaces, not concrete module dependencies: {path}")
        if not isinstance(module.get("requires_interfaces"), list):
            raise ValueError(f"invalid interface dependencies: {path}")
        if not isinstance(module.get("implements"), str) or not isinstance(module.get("entrypoint"), str):
            raise ValueError(f"missing locally provided interface or entrypoint: {path}")
        if not INTERFACE.fullmatch(module["implements"]):
            raise ValueError(f"invalid provided interface: {key}")
        if bindings.get(module["implements"]) != key:
            raise ValueError(f"unbound implementation: {key} -> {module['implements']}")
        methods = module.get("provides", {}).get(module["implements"])
        if not isinstance(methods, dict) or not methods:
            raise ValueError(f"missing local method descriptions: {key}")
        for name, operation in methods.items():
            if not IDENTIFIER.fullmatch(name) or not isinstance(operation, dict):
                raise ValueError(f"invalid operation: {key}.{name}")
            filename, args = operation.get("script"), operation.get("args")
            if not isinstance(filename, str) or not SCRIPT.fullmatch(filename) or not (path.parent / filename).is_file():
                raise ValueError(f"missing provider script: {key}/{filename}")
            if not isinstance(args, dict) or any(not IDENTIFIER.fullmatch(arg) or typ != "string" for arg, typ in args.items()):
                raise ValueError(f"invalid local signature: {key}.{name}")
        if module["entrypoint"] not in methods or methods[module["entrypoint"]]["args"]:
            raise ValueError(f"entrypoint must have no arguments: {key}")
        modules[key] = module

    for interface, provider in bindings.items():
        if not INTERFACE.fullmatch(interface) or provider not in modules or modules[provider]["implements"] != interface:
            raise ValueError(f"invalid binding: {interface} -> {provider}")

    for key, module in modules.items():
        required = module["requires_interfaces"]
        if any(not isinstance(req, dict) or "interface" not in req or "operations" not in req for req in required):
            raise ValueError(f"invalid required interfaces: {key}")
        required_by_name = {req["interface"]: req["operations"] for req in required}
        if len(required_by_name) != len(required):
            raise ValueError(f"duplicate required interface: {key}")
        if module["substrate"] != "native" and module["substrate"] not in required_by_name:
            raise ValueError(f"substrate must be a required interface: {key}")
        dependencies = []
        for interface, expected in required_by_name.items():
            if not INTERFACE.fullmatch(interface) or interface not in bindings:
                raise ValueError(f"unbound interface: {interface}")
            provider = bindings[interface]
            if provider == key:
                raise ValueError(f"module cannot depend on itself as provider: {key}")
            if not isinstance(expected, dict) or not expected:
                raise ValueError(f"empty method requirements: {key} -> {interface}")
            actual = modules[provider]["provides"][interface]
            for operation, signature in expected.items():
                if operation not in actual or not isinstance(signature, dict) or signature.get("args") != actual[operation]["args"]:
                    raise ValueError(f"incompatible interface method: {key} -> {interface}.{operation}")
            dependencies.append(provider)
        calls = []
        for call in module.get("calls", []):
            interface, operation, args = call["interface"], call["operation"], call["args"]
            if interface not in required_by_name or operation not in required_by_name[interface]:
                raise ValueError(f"undeclared method dependency: {key} -> {interface}.{operation}")
            expected = required_by_name[interface][operation]["args"]
            if not isinstance(args, dict) or set(args) != set(expected) or any(not isinstance(args[name], str) for name in expected):
                raise ValueError(f"signature mismatch: {key} calls {interface}.{operation}")
            provider = bindings[interface]
            filename = modules[provider]["provides"][interface][operation]["script"]
            calls.append((provider, filename, interface.split("@")[0], operation, args))
        module["_dependencies"] = dependencies
        module["_calls"] = calls

    ordered, visiting, visited = [], set(), set()
    def visit(key):
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
        filename = module["provides"][module["implements"]][module["entrypoint"]]["script"]
        lines += [f"    - name: {module['id']} implements {module['implements']}.{module['entrypoint']}",
                  f"      ansible.builtin.import_tasks: modules/{module['id']}/{filename}"]
        for provider, filename, interface, operation, args in module["_calls"]:
            lines += [f"    - name: {module['id']} calls {interface}.{operation}",
                      f"      ansible.builtin.include_tasks: modules/{provider}/{filename}", "      vars:"]
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
