#!/usr/bin/env python3
"""Pure instance expansion and a minimal, interface-dispatched shell executor."""
import json
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
INTERFACE = re.compile(r"[a-z][a-z0-9-]*@[1-9][0-9]*\Z")
ARG = re.compile(r"[a-z][a-z0-9_]*\Z")
SCRIPT = re.compile(r"[a-z][a-z0-9-]*\.sh\Z")
ABSOLUTE_PATH = re.compile(r"/[A-Za-z0-9_./-]+\Z")
TYPES = ("string", "absolute-path")


def valid_signature(signature):
    return isinstance(signature, dict) and all(isinstance(k, str) and ARG.fullmatch(k) and v in TYPES
                                                    for k, v in signature.items())


def valid_value(value, kind):
    if kind == "string":
        return isinstance(value, str)
    if kind == "absolute-path":
        return isinstance(value, str) and bool(ABSOLUTE_PATH.fullmatch(value)) and ".." not in value.split("/")
    return False


def load(root):
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
        for key, spec in values.items():
            if (not isinstance(key, str) or not ARG.fullmatch(key) or not isinstance(spec, dict)
                    or spec.get("type") not in TYPES or not spec.get("guarantee")):
                raise ValueError(f"invalid interface value: {identifier}.{key}")
        for key, spec in transitions.items():
            if (not isinstance(key, str) or not ARG.fullmatch(key) or not isinstance(spec, dict)
                    or not valid_signature(spec.get("args")) or not spec.get("guarantee")):
                raise ValueError(f"invalid interface transition: {identifier}.{key}")
        interfaces[identifier] = contract

    modules = {}
    for file in sorted((root / "modules").glob("*/module.json")):
        module = json.loads(file.read_text())
        identifier = module["id"]
        if (not isinstance(identifier, str) or not NAME.fullmatch(identifier)
                or identifier != file.parent.name or identifier in modules):
            raise ValueError(f"invalid or duplicate module: {file}")
        provided = module["implements"]
        if (not isinstance(provided, list) or not provided or len(provided) != len(set(provided))
                or any(i not in interfaces for i in provided)):
            raise ValueError(f"unknown or duplicate provided interface: {identifier}")
        required = module.get("requires")
        if (not isinstance(required, list) or len(required) != len(set(required))
                or any(i not in interfaces for i in required)):
            raise ValueError(f"unknown or duplicate required interface: {identifier}")
        entry = module["entrypoint"]
        if (not isinstance(entry, dict) or set(entry) != {"interface", "transition"}
                or entry["interface"] not in provided
                or entry["transition"] not in interfaces[entry["interface"]]["transitions"]
                or interfaces[entry["interface"]]["transitions"][entry["transition"]]["args"]):
            raise ValueError(f"invalid no-argument entrypoint: {identifier}")
        values, transitions = module.get("values"), module.get("transitions")
        if not isinstance(values, dict) or set(values) != set(provided) or not isinstance(transitions, dict) or set(transitions) != set(provided):
            raise ValueError(f"incomplete provided interface: {identifier}")
        uses = module.get("uses", [])
        if not isinstance(uses, list):
            raise ValueError(f"invalid static uses: {identifier}")
        dynamic = {i: set() for i in provided}
        for use in uses:
            if (not isinstance(use, dict) or set(use) != {"interface", "value", "as"}
                    or use["interface"] not in required
                    or use["value"] not in interfaces[use["interface"]]["values"]
                    or not isinstance(use["as"], str) or not ARG.fullmatch(use["as"])):
                raise ValueError(f"invalid static use: {identifier}")
            # A use supplies a provided value if names and types match; otherwise it supplies an argument.
            for interface in provided:
                if use["as"] in interfaces[interface]["values"]:
                    if interfaces[interface]["values"][use["as"]]["type"] != interfaces[use["interface"]]["values"][use["value"]]["type"]:
                        raise ValueError(f"incompatible static value: {identifier}.{use['as']}")
                    dynamic[interface].add(use["as"])
        for interface in provided:
            specs = interfaces[interface]["values"]
            if not isinstance(values[interface], dict) or set(values[interface]) | dynamic[interface] != set(specs) or set(values[interface]) & dynamic[interface]:
                raise ValueError(f"incomplete provided values: {identifier}.{interface}")
            for key, value in values[interface].items():
                if not valid_value(value, specs[key]["type"]):
                    raise ValueError(f"invalid provided value: {identifier}.{key}")
            declared = interfaces[interface]["transitions"]
            if not isinstance(transitions[interface], dict) or set(transitions[interface]) != set(declared):
                raise ValueError(f"incomplete transitions: {identifier}.{interface}")
            for name, script in transitions[interface].items():
                if script is not None and (not isinstance(script, str) or not SCRIPT.fullmatch(script) or not (file.parent / script).is_file()):
                    raise ValueError(f"missing transition script: {identifier}.{name}")
        if not valid_signature(module.get("config", {})) or not isinstance(module.get("calls", []), list):
            raise ValueError(f"invalid config or calls: {identifier}")
        own_script = transitions[entry["interface"]][entry["transition"]]
        if (own_script is None) == (not module.get("calls", [])):
            raise ValueError(f"entrypoint needs either a script or delegated calls: {identifier}")
        modules[identifier] = module
    return interfaces, modules


def expand(root=ROOT):
    """Resolve bindings and static values without touching a target."""
    interfaces, modules = load(root)
    instances = {}
    for file in sorted((root / "instances").glob("*.json")):
        instance = json.loads(file.read_text())
        identifier = instance["id"]
        if (not isinstance(identifier, str) or not NAME.fullmatch(identifier) or identifier != file.stem
                or identifier in instances or instance["module"] not in modules):
            raise ValueError(f"invalid instance: {file}")
        instances[identifier] = instance
    for identifier, instance in instances.items():
        module = modules[instance["module"]]
        bindings = instance.get("bindings", {})
        if not isinstance(bindings, dict) or set(bindings) != set(module["requires"]):
            raise ValueError(f"missing or unexpected binding: {identifier}")
        for interface, provider in bindings.items():
            if provider not in instances or provider == identifier:
                raise ValueError(f"unknown or self provider: {identifier} -> {provider}")
            if interface not in modules[instances[provider]["module"]]["implements"]:
                raise ValueError(f"binding does not provide {interface}: {identifier} -> {provider}")
        config = instance.get("inputs", {})
        if not isinstance(config, dict) or set(config) != set(module.get("config", {})):
            raise ValueError(f"missing or unexpected instance config: {identifier}")
        for key, value in config.items():
            if not valid_value(value, module["config"][key]):
                raise ValueError(f"invalid instance config: {identifier}.{key}")

    ordered, active, done = [], set(), set()
    def visit(identifier):
        if identifier in active:
            raise ValueError(f"dependency cycle: {identifier}")
        if identifier in done:
            return
        active.add(identifier)
        for provider in instances[identifier].get("bindings", {}).values():
            visit(provider)
        active.remove(identifier)
        done.add(identifier)
        ordered.append(identifier)
    for identifier in instances:
        visit(identifier)

    expanded = {}
    for identifier in ordered:
        instance = instances[identifier]
        module = modules[instance["module"]]
        bindings = instance.get("bindings", {})
        values = {interface: dict(v) for interface, v in module["values"].items()}
        args = {key: {"value": value, "source": "config"} for key, value in instance.get("inputs", {}).items()}
        for use in module.get("uses", []):
            interface, key, dest = use["interface"], use["value"], use["as"]
            provider_id = bindings[interface]
            source_value = expanded[provider_id]["provided"][interface][key]
            source = {"interface": interface, "instance": provider_id, "value": key}
            destinations = [i for i in module["implements"] if dest in interfaces[i]["values"]]
            if destinations:
                for provided in destinations:
                    values[provided][dest] = source_value
            else:
                if dest in args:
                    raise ValueError(f"duplicate argument: {identifier}.{dest}")
                args[dest] = {"value": source_value, "source": source}
        actions = []
        entry = module["entrypoint"]
        script = module["transitions"][entry["interface"]][entry["transition"]]
        if script is not None:
            actions.append({"provider": identifier, "interface": entry["interface"], "transition": entry["transition"],
                            "module": module["id"], "script": script, "args": []})
        for call in module.get("calls", []):
            if not isinstance(call, dict) or set(call) != {"interface", "transition", "args"}:
                raise ValueError(f"invalid call: {identifier}")
            interface, transition = call["interface"], call["transition"]
            if interface not in bindings or transition not in interfaces[interface]["transitions"]:
                raise ValueError(f"unknown required transition: {identifier}")
            signature = interfaces[interface]["transitions"][transition]["args"]
            if not isinstance(call["args"], dict) or set(call["args"]) != set(signature):
                raise ValueError(f"incorrect call arguments: {identifier}")
            passed = []
            for name, kind in signature.items():
                source = call["args"][name]
                available = {**{k: v["value"] for k, v in args.items()}, **values[entry["interface"]]}
                if source not in available or not valid_value(available[source], kind):
                    raise ValueError(f"invalid call argument: {identifier}.{name}")
                passed.append(available[source])
            provider_id = bindings[interface]
            provider = modules[instances[provider_id]["module"]]
            script = provider["transitions"][interface][transition]
            if script is None:
                raise ValueError(f"required transition has no substrate implementation: {identifier} -> {interface}.{transition}")
            actions.append({"provider": provider_id, "interface": interface, "transition": transition,
                            "module": provider["id"], "script": script, "args": passed})
        expanded[identifier] = {"id": identifier, "module": module["id"], "interface": entry["interface"],
                                "dependencies": list(bindings.values()), "provided": values, "args": args,
                                "actions": actions}
    return [expanded[identifier] for identifier in ordered]


def script(expanded, root=ROOT):
    """Render bound substrate scripts for an explicitly confirmed disposable VM; do not execute."""
    lines = ["#!/bin/sh", "set -eu",
             "[ \"${AGENTIC_DISPOSABLE_VM:-}\" = true ] && [ \"${AGENTIC_CONSOLE_VERIFIED:-}\" = true ] || { echo 'Disposable VM and console confirmation required' >&2; exit 1; }",
             "[ \"$(id -u)\" -eq 0 ] || { echo 'Run as root on the target' >&2; exit 1; }"]
    count = 0
    for instance in expanded:
        for action in instance["actions"]:
            path = root / "modules" / action["module"] / action["script"]
            content = path.read_text()
            delimiter = f"AGENTIC_TASK_{count}"
            if delimiter in content:
                raise ValueError("script contains its here-document delimiter")
            arguments = " ".join(shlex.quote(arg) for arg in action["args"])
            lines.extend([f"# {instance['id']}: {action['interface']}.{action['transition']} on {action['provider']}",
                          f"sh -s -- {arguments} <<'{delimiter}'", content.rstrip("\n"), delimiter])
            count += 1
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        expanded = expand()
        if sys.argv[1:] == ["--expand"]:
            print(json.dumps(expanded, indent=2))
        elif sys.argv[1:] == ["--script"]:
            print(script(expanded), end="")
        else:
            raise ValueError("usage: plan.py [--expand | --script]")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
