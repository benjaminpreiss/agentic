#!/usr/bin/env python3
"""Expand interface-bound instances, then render their concrete module scripts."""
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
        if not isinstance(contract.get("values"), dict):
            raise ValueError(f"invalid interface values: {identifier}")
        lookups, transitions = contract.get("lookups", {}), contract.get("transitions")
        if not isinstance(lookups, dict) or not isinstance(transitions, dict) or not transitions:
            raise ValueError(f"invalid interface contract: {identifier}")
        for method, spec in lookups.items():
            if (not isinstance(method, str) or not ARG.fullmatch(method) or not isinstance(spec, dict)
                    or spec.get("args") != {} or spec.get("returns") not in TYPES or not spec.get("guarantee")):
                raise ValueError(f"invalid static lookup: {identifier}.{method}")
        for method, spec in transitions.items():
            if (not isinstance(method, str) or not ARG.fullmatch(method) or not isinstance(spec, dict)
                    or not valid_signature(spec.get("args")) or not spec.get("guarantee")):
                raise ValueError(f"invalid transition: {identifier}.{method}")
        interfaces[identifier] = contract

    modules = {}
    for file in sorted((root / "modules").glob("*/module.json")):
        module = json.loads(file.read_text())
        identifier = module["id"]
        if (not isinstance(identifier, str) or not NAME.fullmatch(identifier)
                or identifier != file.parent.name or identifier in modules):
            raise ValueError(f"invalid or duplicate module: {file}")
        interface = module["implements"]
        if interface not in interfaces:
            raise ValueError(f"unknown implemented interface: {identifier} -> {interface}")
        contract = interfaces[interface]
        required = module.get("requires")
        if (not isinstance(required, list) or len(required) != len(set(required))
                or any(i not in interfaces for i in required)):
            raise ValueError(f"unknown or duplicate required interface: {identifier}")
        lookups = module.get("lookups", {})
        if not isinstance(lookups, dict) or set(lookups) != set(contract.get("lookups", {})):
            raise ValueError(f"incomplete lookups: {identifier}")
        for method, value in lookups.items():
            if not valid_value(value, contract["lookups"][method]["returns"]):
                raise ValueError(f"invalid lookup declaration: {identifier}.{method}")
        transitions = module.get("transitions")
        if not isinstance(transitions, dict) or set(transitions) != set(contract["transitions"]):
            raise ValueError(f"incomplete transitions: {identifier}")
        for method, script in transitions.items():
            if not isinstance(script, str) or not SCRIPT.fullmatch(script) or not (file.parent / script).is_file():
                raise ValueError(f"missing transition script: {identifier}.{method}")
        entrypoint = module["entrypoint"]
        if entrypoint not in transitions or contract["transitions"][entrypoint]["args"]:
            raise ValueError(f"invalid no-argument entrypoint: {identifier}")
        if not valid_signature(module.get("config", {})):
            raise ValueError(f"invalid instance config signature: {identifier}")
        uses = module.get("uses", [])
        if not isinstance(uses, list):
            raise ValueError(f"invalid static uses: {identifier}")
        destinations = set(module.get("config", {})) | set(lookups)
        for use in uses:
            if (not isinstance(use, dict) or set(use) != {"interface", "lookup", "args", "as"}
                    or use["interface"] not in required or use["lookup"] not in interfaces[use["interface"]].get("lookups", {})
                    or use["args"] != {} or not isinstance(use["as"], str) or not ARG.fullmatch(use["as"])
                    or use["as"] in destinations):
                raise ValueError(f"invalid static use: {identifier}")
            destinations.add(use["as"])
        script_args = module.get("script_args")
        if (not isinstance(script_args, list) or len(script_args) != len(set(script_args))
                or any(name not in destinations for name in script_args)):
            raise ValueError(f"invalid private script arguments: {identifier}")
        modules[identifier] = module
    return interfaces, modules


def expand(root=ROOT):
    """Pure expansion: resolve instance bindings and module-owned static lookups."""
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
            if interface != modules[instances[provider]["module"]]["implements"]:
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
        args = {key: {"value": value, "source": "config"} for key, value in instance.get("inputs", {}).items()}
        for use in module.get("uses", []):
            provider_id = bindings[use["interface"]]
            provider = expanded[provider_id]
            method = use["lookup"]
            value = provider["lookups"][method]
            args[use["as"]] = {"value": value, "source": {"interface": use["interface"],
                                    "instance": provider_id, "lookup": method}}
        available = {**{name: item["value"] for name, item in args.items()}, **module["lookups"]}
        action = {"provider": identifier, "interface": module["implements"], "transition": module["entrypoint"],
                  "module": module["id"], "script": module["transitions"][module["entrypoint"]],
                  "args": [available[name] for name in module["script_args"]]}
        expanded[identifier] = {"id": identifier, "module": module["id"], "interface": module["implements"],
                                "dependencies": list(bindings.values()), "lookups": module["lookups"],
                                "args": args, "actions": [action]}
    return [expanded[identifier] for identifier in ordered]


def script(expanded, root=ROOT):
    """Render bound module scripts for an explicitly confirmed disposable VM; do not execute."""
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
            lines.extend([f"# {instance['id']}: {action['interface']}.{action['transition']}",
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
