#!/usr/bin/env python3
"""Select explicit JSON transitions between recorded and desired module instances."""
import json
import re
import shlex
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
INTERFACE = re.compile(r"[a-z][a-z0-9-]*@[1-9][0-9]*\Z")
ARG = re.compile(r"[a-z][a-z0-9_]*\Z")
PATH = re.compile(r"/[A-Za-z0-9_./-]+\Z")


def value_is(value, kind):
    if kind == "string":
        return isinstance(value, str)
    if kind == "absolute-path":
        return isinstance(value, str) and bool(PATH.fullmatch(value)) and ".." not in value.split("/")
    return False


def documents(directory, key):
    result = {}
    for file in sorted(directory.glob("*/" + key + ".json") if key in ("module", "transition")
                       else directory.glob("*.json")):
        doc = json.loads(file.read_text())
        name = doc["id"]
        if (not isinstance(name, str) or not NAME.fullmatch(name) or name in result
                or (file.parent.name if key in ("module", "transition") else file.stem) != name):
            raise ValueError(f"invalid or duplicate {key}: {file}")
        result[name] = doc
    return result


def load(root):
    interfaces = {}
    for file in sorted((root / "interfaces").glob("*.json")):
        doc = json.loads(file.read_text())
        name = doc["id"]
        if not isinstance(name, str) or not INTERFACE.fullmatch(name):
            raise ValueError(f"invalid interface: {file}")
        stem, version = name.rsplit("@", 1)
        if file.name != f"{stem}.v{version}.json" or name in interfaces or not isinstance(doc.get("values"), dict):
            raise ValueError(f"invalid or duplicate interface: {file}")
        for key, spec in doc["values"].items():
            if (not isinstance(key, str) or not ARG.fullmatch(key) or not isinstance(spec, dict)
                    or spec.get("type") not in ("string", "absolute-path") or not spec.get("guarantee")):
                raise ValueError(f"invalid interface value: {name}.{key}")
        if "transitions" in doc or "scripts" in doc:
            raise ValueError(f"interfaces describe capabilities, not deployment transitions: {name}")
        interfaces[name] = doc

    modules = documents(root / "modules", "module")
    for name, mod in modules.items():
        interface = mod.get("implements")
        if interface not in interfaces or "transitions" in mod or "scripts" in mod or "entrypoint" in mod:
            raise ValueError(f"invalid module capabilities: {name}")
        required = mod.get("requires")
        if (not isinstance(required, list) or len(required) != len(set(required))
                or any(i not in interfaces for i in required)):
            raise ValueError(f"invalid required interfaces: {name}")
        declared = mod.get("values")
        if not isinstance(declared, dict) or set(declared) != set(interfaces[interface]["values"]):
            raise ValueError(f"incomplete provided values: {name}")
        for key, value in declared.items():
            if not value_is(value, interfaces[interface]["values"][key]["type"]):
                raise ValueError(f"invalid provided value: {name}.{key}")
        config, uses = mod.get("config", {}), mod.get("uses", [])
        if (not isinstance(config, dict) or any(not isinstance(k, str) or not ARG.fullmatch(k) or v != "string"
                for k, v in config.items()) or not isinstance(uses, list)):
            raise ValueError(f"invalid module config or uses: {name}")
        dests = set(config) | set(declared)
        for use in uses:
            if (not isinstance(use, dict) or set(use) != {"interface", "value", "as"}
                    or use["interface"] not in required or use["value"] not in interfaces[use["interface"]]["values"]
                    or not isinstance(use["as"], str) or not ARG.fullmatch(use["as"])
                    or use["as"] in dests):
                raise ValueError(f"invalid module use: {name}")
            dests.add(use["as"])

    transitions = documents(root / "transitions", "transition")
    keys = set()
    for name, transition in transitions.items():
        start, end, interface = transition.get("start"), transition.get("end"), transition.get("interface")
        if start is None and end is None:
            raise ValueError(f"transition needs a start or end module: {name}")
        if (interface not in interfaces or any(m is not None and
                (m not in modules or modules[m]["implements"] != interface) for m in (start, end))):
            raise ValueError(f"transition endpoint does not implement {interface}: {name}")
        key = (interface, start, end)
        if key in keys:
            raise ValueError(f"ambiguous transition: {name}")
        keys.add(key)
        script = transition.get("script")
        if script != "run.sh" or not (root / "transitions" / name / script).is_file():
            raise ValueError(f"missing transition script: {name}")
        args = transition.get("args")
        if not isinstance(args, list):
            raise ValueError(f"invalid transition arguments: {name}")
        for arg in args:
            if (not isinstance(arg, dict) or set(arg) != {"side", "name"}
                    or arg["side"] not in ("start", "end") or not isinstance(arg["name"], str)
                    or not ARG.fullmatch(arg["name"]) or transition[arg["side"]] is None):
                raise ValueError(f"invalid transition argument: {name}")
    return interfaces, modules, transitions


def read_desired(root):
    desired = documents(root / "instances", "instance")
    for name, instance in desired.items():
        if (instance.get("module") is None and (instance.get("bindings", {}) or instance.get("inputs", {}))):
            raise ValueError(f"removed instance cannot have desired bindings or inputs: {name}")
    return desired


def read_previous(file):
    previous = json.loads(file.read_text())["instances"]
    if not isinstance(previous, dict) or any(not isinstance(entry, dict) or "module" not in entry
                                              for entry in previous.values()):
        raise ValueError("invalid previous deployment record")
    return previous


def resolve(name, entries, modules, interfaces):
    """Resolve the static declaration on one side of a transition (never inspect a host)."""
    instance = entries[name]
    mod = modules[instance["module"]]
    bindings = instance.get("bindings", {})
    if not isinstance(bindings, dict) or set(bindings) != set(mod["requires"]):
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
                or modules[entries[provider]["module"]]["implements"] != interface):
            raise ValueError(f"binding does not provide {interface}: {name} -> {provider}")
    for use in mod.get("uses", []):
        interface, key = use["interface"], use["value"]
        provider = bindings[interface]
        args[use["as"]] = {"value": modules[entries[provider]["module"]]["values"][key],
                           "source": {"interface": interface, "instance": provider, "value": key}}
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
        for provider in entries[name].get("bindings", {}).values():
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


def expand(root=ROOT, previous_file=None):
    """Select exact start→end transitions using an explicit previous-state record."""
    if previous_file is None:
        previous_file = root / "state" / "absent.json"
    interfaces, modules, transitions = load(root)
    desired, previous = read_desired(root), read_previous(Path(previous_file))
    if set(desired) != set(previous):
        raise ValueError("previous record must explicitly name every desired instance, including absent ones")
    for name in previous:
        if previous[name]["module"] is not None and previous[name]["module"] not in modules:
            raise ValueError(f"previous module declaration unavailable: {name}")
        if desired[name]["module"] is not None and desired[name]["module"] not in modules:
            raise ValueError(f"unknown desired module: {name}")

    active = [n for n in desired if desired[n]["module"] is not None]
    removed = [n for n in previous if previous[n]["module"] is not None and desired[n]["module"] is None]
    ordered = order(active, desired) + list(reversed(order(removed, previous)))
    index = {(t["interface"], t["start"], t["end"]): t for t in transitions.values()}
    plan = []
    for name in ordered:
        before, after = previous[name]["module"], desired[name]["module"]
        old = resolve(name, previous, modules, interfaces) if before is not None else None
        new = resolve(name, desired, modules, interfaces) if after is not None else None
        interface = (new or old)["interface"]
        transition = index.get((interface, before, after))
        if transition is None:
            raise ValueError(f"no explicit transition for {name}: {before} -> {after}")
        args = []
        for arg in transition["args"]:
            endpoint = old if arg["side"] == "start" else new
            if arg["name"] not in endpoint["args"]:
                raise ValueError(f"unknown transition argument: {transition['id']}.{arg['name']}")
            args.append({"value": endpoint["args"][arg["name"]]["value"], "source":
                        {"side": arg["side"], "detail": endpoint["args"][arg["name"]]["source"]}})
        plan.append({"instance": name, "transition": transition["id"], "interface": interface,
                     "start": before, "end": after, "dependencies": list((new or old)["bindings"].values()),
                     "script": f"transitions/{transition['id']}/run.sh", "args": args})
    return plan


def script(plan, root=ROOT):
    """Render selected transitions; does not touch the target or update applied state."""
    lines = ["#!/bin/sh", "set -eu",
             "[ \"${AGENTIC_DISPOSABLE_VM:-}\" = true ] && [ \"${AGENTIC_CONSOLE_VERIFIED:-}\" = true ] || { echo 'Disposable VM and console confirmation required' >&2; exit 1; }",
             "[ \"$(id -u)\" -eq 0 ] || { echo 'Run as root on the target' >&2; exit 1; }"]
    for number, step in enumerate(plan):
        content = (root / step["script"]).read_text().rstrip("\n")
        marker = f"AGENTIC_TRANSITION_{number}"
        if marker in content:
            raise ValueError("transition script contains its here-document delimiter")
        args = " ".join(shlex.quote(arg["value"]) for arg in step["args"])
        lines.extend([f"# {step['instance']}: {step['transition']} ({step['start']} -> {step['end']})",
                      f"sh -s -- {args} <<'{marker}'", content, marker])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        if len(sys.argv) != 4 or sys.argv[1] != "--from" or sys.argv[3] not in ("--expand", "--script"):
            raise ValueError("usage: plan.py --from state/absent.json [--expand | --script]")
        planned = expand(previous_file=Path(sys.argv[2]))
        if sys.argv[3] == "--expand":
            print(json.dumps(planned, indent=2))
        else:
            print(script(planned), end="")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
