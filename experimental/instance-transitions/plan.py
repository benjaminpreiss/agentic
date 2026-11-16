#!/usr/bin/env python3
"""Expand explicitly requested transitions between identified module artifacts."""
import json
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
ARG = re.compile(r"[a-z][a-z0-9_]*\Z")
DID = re.compile(r"did:[a-z0-9]+:[A-Za-z0-9._:%-]+\Z")
PATH = re.compile(r"/[A-Za-z0-9_./-]+\Z")
ID_FIELDS = {"kind", "publisher", "name", "version"}


def artifact_id(raw, kind):
    """Canonical in-process key. A DID is an opaque claim, NOT resolved or authenticated here."""
    if (not isinstance(raw, dict) or set(raw) != ID_FIELDS or raw["kind"] != kind
            or not isinstance(raw["publisher"], str) or not DID.fullmatch(raw["publisher"])
            or not isinstance(raw["name"], str) or not NAME.fullmatch(raw["name"])
            or type(raw["version"]) is not int or raw["version"] < 1):
        raise ValueError(f"invalid {kind} identity: {raw!r}")
    return (kind, raw["publisher"], raw["name"], raw["version"])


def value_is(value, kind):
    if kind == "string":
        return isinstance(value, str)
    if kind == "absolute-path":
        return isinstance(value, str) and bool(PATH.fullmatch(value)) and ".." not in value.split("/")
    return False


def documents(root, kind):
    result = {}
    for file in sorted((root / (kind + "s")).rglob(kind + ".json")):
        doc = json.loads(file.read_text())
        key = artifact_id(doc.get("id"), kind)
        if key in result:
            raise ValueError(f"duplicate artifact identity: {doc['id']}")
        doc["_file"] = file.relative_to(root)
        result[key] = doc
    return result


def load(root):
    interfaces = {}
    for file in sorted((root / "interfaces").rglob("*.json")):
        doc = json.loads(file.read_text())
        key = artifact_id(doc.get("id"), "interface")
        if key in interfaces or not isinstance(doc.get("values"), dict):
            raise ValueError(f"invalid or duplicate interface: {file}")
        for name, spec in doc["values"].items():
            if (not isinstance(name, str) or not ARG.fullmatch(name) or not isinstance(spec, dict)
                    or spec.get("type") not in ("string", "absolute-path") or not spec.get("guarantee")):
                raise ValueError(f"invalid interface value: {file}.{name}")
        if "transitions" in doc or "scripts" in doc:
            raise ValueError(f"interface contains deployment effects: {file}")
        interfaces[key] = doc

    modules = documents(root, "module")
    for key, mod in modules.items():
        interface = artifact_id(mod.get("implements"), "interface")
        if interface not in interfaces or any(k in mod for k in ("transitions", "scripts", "entrypoint")):
            raise ValueError(f"invalid module capabilities: {mod['id']}")
        required = mod.get("requires")
        if not isinstance(required, list):
            raise ValueError(f"invalid required interfaces: {mod['id']}")
        required_ids = [artifact_id(i, "interface") for i in required]
        if len(set(required_ids)) != len(required_ids) or any(i not in interfaces for i in required_ids):
            raise ValueError(f"invalid required interfaces: {mod['id']}")
        declared = mod.get("values")
        if not isinstance(declared, dict) or set(declared) != set(interfaces[interface]["values"]):
            raise ValueError(f"incomplete provided values: {mod['id']}")
        for name, value in declared.items():
            if not value_is(value, interfaces[interface]["values"][name]["type"]):
                raise ValueError(f"invalid provided value: {mod['id']}.{name}")
        config, uses = mod.get("config", {}), mod.get("uses", [])
        if (not isinstance(config, dict) or any(not isinstance(k, str) or not ARG.fullmatch(k) or v != "string"
                for k, v in config.items()) or not isinstance(uses, list)):
            raise ValueError(f"invalid module config or uses: {mod['id']}")
        dests = set(config) | set(declared)
        for use in uses:
            if not isinstance(use, dict) or set(use) != {"interface", "value", "as"}:
                raise ValueError(f"invalid module use: {mod['id']}")
            source = artifact_id(use["interface"], "interface")
            if (source not in required_ids or use["value"] not in interfaces[source]["values"]
                    or not isinstance(use["as"], str) or not ARG.fullmatch(use["as"])
                    or use["as"] in dests):
                raise ValueError(f"invalid module use: {mod['id']}")
            dests.add(use["as"])

    transitions = documents(root, "transition")
    for key, transition in transitions.items():
        source, destination = transition.get("from"), transition.get("to")
        if source is None and destination is None:
            raise ValueError(f"transition needs a from or to module: {transition['id']}")
        interface = artifact_id(transition.get("interface"), "interface")
        if interface not in interfaces:
            raise ValueError(f"unknown transition interface: {transition['id']}")
        for endpoint in (source, destination):
            if endpoint is not None:
                module_id = artifact_id(endpoint, "module")
                if module_id not in modules or artifact_id(modules[module_id]["implements"], "interface") != interface:
                    raise ValueError(f"transition endpoint does not implement interface: {transition['id']}")
        if transition.get("script") != "run.sh" or not (root / transition["_file"].parent / "run.sh").is_file():
            raise ValueError(f"missing transition script: {transition['id']}")
        args = transition.get("args")
        if not isinstance(args, list):
            raise ValueError(f"invalid transition arguments: {transition['id']}")
        for arg in args:
            if (not isinstance(arg, dict) or set(arg) != {"side", "name"}
                    or arg["side"] not in ("from", "to") or not isinstance(arg["name"], str)
                    or not ARG.fullmatch(arg["name"]) or transition.get(arg["side"]) is None):
                raise ValueError(f"invalid transition argument: {transition['id']}")
    return interfaces, modules, transitions


def read_desired(root):
    result = {}
    for file in sorted((root / "instances").glob("*.json")):
        doc = json.loads(file.read_text())
        name = doc.get("id")
        if not isinstance(name, str) or not NAME.fullmatch(name) or file.stem != name or name in result:
            raise ValueError(f"invalid or duplicate instance: {file}")
        if "module" not in doc:
            raise ValueError(f"missing desired module: {name}")
        if doc["module"] is None:
            if doc.get("bindings", []) or doc.get("inputs", {}):
                raise ValueError(f"removed instance cannot have desired bindings or inputs: {name}")
        else:
            artifact_id(doc["module"], "module")
        result[name] = doc
    return result


def read_requests(file, transitions):
    requested = json.loads(file.read_text())["transitions"]
    if not isinstance(requested, list):
        raise ValueError("invalid transition requests")
    by_instance = {}
    for entry in requested:
        if (not isinstance(entry, dict) or not {"instance", "transition"}.issubset(entry)
                or set(entry) - {"instance", "transition", "from_inputs", "from_bindings"}
                or not isinstance(entry["instance"], str) or entry["instance"] in by_instance):
            raise ValueError("invalid or duplicate transition request")
        transition_id = artifact_id(entry["transition"], "transition")
        if transition_id not in transitions:
            raise ValueError(f"unknown requested transition: {entry['instance']}")
        by_instance[entry["instance"]] = entry
    return by_instance


def bindings_for(entry):
    bindings = entry.get("bindings", [])
    if not isinstance(bindings, list):
        raise ValueError("bindings must be a list of interface/instance pairs")
    result = {}
    for binding in bindings:
        if not isinstance(binding, dict) or set(binding) != {"interface", "instance"}:
            raise ValueError("invalid binding")
        interface = artifact_id(binding["interface"], "interface")
        if interface in result or not isinstance(binding["instance"], str):
            raise ValueError("duplicate or invalid binding")
        result[interface] = binding["instance"]
    return result


def resolve(name, entries, modules, interfaces):
    """Resolve the static declaration on one side of a transition (never inspect a host)."""
    instance = entries[name]
    mod = modules[artifact_id(instance["module"], "module")]
    bindings = bindings_for(instance)
    required = {artifact_id(i, "interface") for i in mod["requires"]}
    if set(bindings) != required:
        raise ValueError(f"missing or unexpected binding: {name}")
    config = instance.get("inputs", {})
    if not isinstance(config, dict) or set(config) != set(mod.get("config", {})):
        raise ValueError(f"missing or unexpected instance config: {name}")
    args = {key: {"value": value, "source": "config"} for key, value in config.items()}
    for key, value in config.items():
        if not value_is(value, mod["config"][key]):
            raise ValueError(f"invalid instance config: {name}.{key}")
    args.update({key: {"value": value, "source": "module"} for key, value in mod["values"].items()})
    for interface, provider in bindings.items():
        if (provider not in entries or entries[provider]["module"] is None or provider == name
                or artifact_id(modules[artifact_id(entries[provider]["module"], "module")]["implements"], "interface") != interface):
            raise ValueError(f"binding does not provide {interface}: {name} -> {provider}")
    for use in mod.get("uses", []):
        interface, value_name = artifact_id(use["interface"], "interface"), use["value"]
        provider = bindings[interface]
        provider_module = modules[artifact_id(entries[provider]["module"], "module")]
        args[use["as"]] = {"value": provider_module["values"][value_name],
                           "source": {"interface": use["interface"], "instance": provider, "value": value_name}}
    return {"module": mod["id"], "interface": mod["implements"], "bindings": bindings, "args": args}


def order(names, entries):
    """Dependencies precede dependents; rejects missing bindings and cycles."""
    ordered, active, done = [], set(), set()
    selected = set(names)
    def visit(name):
        if name in active:
            raise ValueError(f"dependency cycle: {name}")
        if name in done:
            return
        active.add(name)
        for provider in bindings_for(entries[name]).values():
            if provider not in entries or entries[provider]["module"] is None:
                raise ValueError(f"unavailable dependency: {name} -> {provider}")
            if provider in selected:
                visit(provider)
        active.remove(name)
        done.add(name)
        ordered.append(name)
    for name in names:
        visit(name)
    return ordered


def expand(root=ROOT, request_file=None):
    """Resolve explicit transition requests; no execution history or target observation."""
    if request_file is None:
        request_file = root / "requests" / "introduction.json"
    interfaces, modules, transitions = load(root)
    desired = read_desired(root)
    requests = read_requests(Path(request_file), transitions)
    if set(desired) != set(requests):
        raise ValueError("requests must explicitly name every desired instance")
    sources = {}
    for name, entry in requests.items():
        transition = transitions[artifact_id(entry["transition"], "transition")]
        if desired[name]["module"] != transition.get("to"):
            raise ValueError(f"requested transition to does not match desired module: {name}")
        if transition.get("from") is None and (entry.get("from_inputs") or entry.get("from_bindings")):
            raise ValueError(f"absent from cannot have bindings or inputs: {name}")
        sources[name] = {"module": transition.get("from"), "inputs": entry.get("from_inputs", {}),
                         "bindings": entry.get("from_bindings", [])}

    active_names = [n for n in desired if desired[n]["module"] is not None]
    removed = [n for n in sources if sources[n]["module"] is not None and desired[n]["module"] is None]
    ordered = order(active_names, desired) + list(reversed(order(removed, sources)))
    plan = []
    for name in ordered:
        transition = transitions[artifact_id(requests[name]["transition"], "transition")]
        before, after = transition.get("from"), transition.get("to")
        old = resolve(name, sources, modules, interfaces) if before is not None else None
        new = resolve(name, desired, modules, interfaces) if after is not None else None
        interface = (new or old)["interface"]
        if interface != transition["interface"]:
            raise ValueError(f"requested transition interface mismatch: {name}")
        args = []
        for arg in transition["args"]:
            endpoint = old if arg["side"] == "from" else new
            if arg["name"] not in endpoint["args"]:
                raise ValueError(f"unknown transition argument: {transition['id']}.{arg['name']}")
            args.append({"value": endpoint["args"][arg["name"]]["value"], "source":
                        {"side": arg["side"], "detail": endpoint["args"][arg["name"]]["source"]}})
        plan.append({"instance": name, "transition": transition["id"], "interface": interface,
                     "from": before, "to": after, "dependencies": list((new or old)["bindings"].values()),
                     "script": str(transition["_file"].parent / "run.sh"), "args": args})
    return plan


def script(plan, root=ROOT):
    """Render requested transitions; does not touch the target or record executions."""
    lines = ["#!/bin/sh", "set -eu",
             "[ \"${AGENTIC_DISPOSABLE_VM:-}\" = true ] && [ \"${AGENTIC_CONSOLE_VERIFIED:-}\" = true ] || { echo 'Disposable VM and console confirmation required' >&2; exit 1; }",
             "[ \"$(id -u)\" -eq 0 ] || { echo 'Run as root on the target' >&2; exit 1; }"]
    for number, step in enumerate(plan):
        content = (root / step["script"]).read_text().rstrip("\n")
        marker = f"AGENTIC_TRANSITION_{number}"
        if marker in content:
            raise ValueError("transition script contains its here-document delimiter")
        args = " ".join(shlex.quote(arg["value"]) for arg in step["args"])
        transition = step["transition"]
        lines.extend([f"# {step['instance']}: {transition['publisher']}/{transition['name']}@{transition['version']}",
                      f"sh -s -- {args} <<'{marker}'", content, marker])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        if len(sys.argv) != 4 or sys.argv[1] != "--requests" or sys.argv[3] not in ("--expand", "--script"):
            raise ValueError("usage: plan.py --requests requests/introduction.json [--expand | --script]")
        planned = expand(request_file=Path(sys.argv[2]))
        if sys.argv[3] == "--expand":
            print(json.dumps(planned, indent=2))
        else:
            print(script(planned), end="")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
