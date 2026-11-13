#!/usr/bin/env python3
"""Expand declarations without contacting a host; render effectful Ansible later."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
INTERFACE = re.compile(r"[a-z][a-z0-9-]*@[1-9][0-9]*\Z")
SCRIPT = re.compile(r"[a-z][a-z0-9-]*\.yml\Z")
ARG = re.compile(r"[a-z][a-z0-9_]*\Z")
ABSOLUTE_PATH = re.compile(r"/[A-Za-z0-9_./-]+\Z")


def valid_signature(signature):
    return isinstance(signature, dict) and all(ARG.fullmatch(k) and v == "string" for k, v in signature.items())


def valid_value(value, kind):
    if kind == "string":
        return isinstance(value, str)
    if kind == "absolute-path":
        return isinstance(value, str) and bool(ABSOLUTE_PATH.fullmatch(value)) and ".." not in value.split("/")
    return False


def expand(root=ROOT):
    """Pure template-data expansion: no target calls, shell discovery or Ansible execution."""
    interfaces = {}
    for file in sorted((root / "interfaces").glob("*.json")):
        contract = json.loads(file.read_text())
        identifier = contract["id"]
        if not isinstance(identifier, str) or not INTERFACE.fullmatch(identifier):
            raise ValueError(f"invalid interface: {file}")
        name, version = identifier.rsplit("@", 1)
        if file.name != f"{name}.v{version}.json" or identifier in interfaces:
            raise ValueError(f"invalid or duplicate interface: {file}")
        values, transitions = contract.get("values"), contract.get("transitions")
        if not isinstance(values, dict) or not isinstance(transitions, dict) or not transitions:
            raise ValueError(f"invalid interface contract: {identifier}")
        for value_name, value_spec in values.items():
            if (not ARG.fullmatch(value_name) or not isinstance(value_spec, dict)
                    or value_spec.get("type") not in ("string", "absolute-path")
                    or not isinstance(value_spec.get("guarantee"), str) or not value_spec["guarantee"]):
                raise ValueError(f"invalid interface value: {identifier}.{value_name}")
        for transition, signature in transitions.items():
            if (not NAME.fullmatch(transition) or not isinstance(signature, dict)
                    or not valid_signature(signature.get("args"))
                    or not isinstance(signature.get("guarantee"), str) or not signature["guarantee"]):
                raise ValueError(f"invalid interface transition: {identifier}.{transition}")
        interfaces[identifier] = contract

    modules = {}
    for file in sorted((root / "modules").glob("*/module.json")):
        module = json.loads(file.read_text())
        identifier = module["id"]
        if not isinstance(identifier, str) or not NAME.fullmatch(identifier) or identifier != file.parent.name or identifier in modules:
            raise ValueError(f"invalid or duplicate module: {file}")
        interface = module["implements"]
        if interface not in interfaces:
            raise ValueError(f"unknown provided interface: {identifier} -> {interface}")
        contract = interfaces[interface]
        scripts = module.get("transitions")
        if not isinstance(scripts, dict) or set(scripts) != set(contract["transitions"]):
            raise ValueError(f"module must implement every transition of {interface}: {identifier}")
        for transition, script in scripts.items():
            if not isinstance(script, str) or not SCRIPT.fullmatch(script) or not (file.parent / script).is_file():
                raise ValueError(f"missing transition script: {identifier}.{transition}")
        entrypoint = contract["transitions"].get(module["entrypoint"])
        if entrypoint is None or entrypoint["args"]:
            raise ValueError(f"entrypoint must have no arguments: {identifier}")
        provided = module.get("values")
        if not isinstance(provided, dict) or set(provided) != set(contract["values"]):
            raise ValueError(f"module must provide every static value of {interface}: {identifier}")
        for value_name, value in provided.items():
            if not valid_value(value, contract["values"][value_name]["type"]):
                raise ValueError(f"invalid provided value: {identifier}.{value_name}")
        required = module.get("requires")
        if not isinstance(required, list) or len(required) != len(set(required)) or any(r not in interfaces for r in required):
            raise ValueError(f"unknown or duplicate required interface: {identifier}")
        if not valid_signature(module.get("config", {})):
            raise ValueError(f"invalid config declaration: {identifier}")
        if not isinstance(module.get("uses", []), list):
            raise ValueError(f"invalid static uses: {identifier}")
        modules[identifier] = module

    instances = {}
    for file in sorted((root / "instances").glob("*.json")):
        instance = json.loads(file.read_text())
        identifier = instance["id"]
        if not isinstance(identifier, str) or not NAME.fullmatch(identifier) or identifier != file.stem or identifier in instances:
            raise ValueError(f"invalid or duplicate instance: {file}")
        if instance["module"] not in modules:
            raise ValueError(f"unknown module: {instance['module']}")
        instance["_module"] = modules[instance["module"]]
        instances[identifier] = instance

    for identifier, instance in instances.items():
        module = instance["_module"]
        bindings = instance.get("bindings", {})
        if not isinstance(bindings, dict) or set(bindings) != set(module["requires"]):
            raise ValueError(f"missing or unexpected binding: {identifier}")
        dependencies = []
        for interface, provider_id in bindings.items():
            if provider_id not in instances or provider_id == identifier:
                raise ValueError(f"unknown or self provider: {identifier} -> {provider_id}")
            if instances[provider_id]["_module"]["implements"] != interface:
                raise ValueError(f"binding does not provide {interface}: {identifier} -> {provider_id}")
            dependencies.append(provider_id)
        config = instance.get("inputs", {})
        if not isinstance(config, dict) or set(config) != set(module.get("config", {})):
            raise ValueError(f"missing or unexpected instance config: {identifier}")
        args = {}
        for arg, value in config.items():
            if not valid_value(value, module["config"][arg]):
                raise ValueError(f"invalid instance config: {identifier}.{arg}")
            args[arg] = {"value": value, "source": "config"}
        for use in module.get("uses", []):
            interface, name, argument = use["interface"], use["value"], use["as"]
            if interface not in bindings or not ARG.fullmatch(argument) or argument in args:
                raise ValueError(f"invalid static use: {identifier}.{argument}")
            spec = interfaces[interface]["values"].get(name)
            if spec is None:
                raise ValueError(f"unknown static value: {identifier} -> {interface}.{name}")
            provider_id = bindings[interface]
            value = instances[provider_id]["_module"]["values"][name]
            args[argument] = {"value": value, "source": {"interface": interface,
                                                        "instance": provider_id, "value": name}}
        instance["_dependencies"] = dependencies
        instance["_args"] = args

    ordered, active, done = [], set(), set()
    def visit(identifier):
        if identifier in active:
            raise ValueError(f"dependency cycle: {identifier}")
        if identifier in done:
            return
        active.add(identifier)
        for dependency in instances[identifier]["_dependencies"]:
            visit(dependency)
        active.remove(identifier)
        done.add(identifier)
        ordered.append(instances[identifier])
    for identifier in instances:
        visit(identifier)
    return [{"id": i["id"], "module": i["_module"]["id"], "interface": i["_module"]["implements"],
             "transition": i["_module"]["entrypoint"], "script": i["_module"]["transitions"][i["_module"]["entrypoint"]],
             "dependencies": i["_dependencies"], "values": i["_module"]["values"], "args": i["_args"]}
            for i in ordered]


def playbook(expanded):
    """Ansible backend for the already expanded declarations."""
    lines = ["---", "- name: Verify expanded declarations on a disposable Tumbleweed VM",
             "  hosts: agentic_vm", "  gather_facts: true", "  become: true", "  tasks:"]
    for instance in expanded:
        lines += [f"    - name: {instance['transition']} {instance['interface']}#{instance['id']}",
                  f"      ansible.builtin.import_tasks: modules/{instance['module']}/{instance['script']}"]
        variables = {f"provided_{name}": value for name, value in instance["values"].items()}
        variables.update({name: value["value"] for name, value in instance["args"].items()})
        if variables:
            lines.append("      vars:")
            lines.extend(f"        {name}: {json.dumps(value)}" for name, value in variables.items())
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        expanded = expand()
        if sys.argv[1:] == ["--expand"]:
            print(json.dumps(expanded, indent=2))
        elif sys.argv[1:] == ["--playbook"]:
            print(playbook(expanded), end="")
        elif not sys.argv[1:]:
            for instance in expanded:
                print(f"{instance['interface']}#{instance['id']}")
        else:
            raise ValueError("usage: plan.py [--expand | --playbook]")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
