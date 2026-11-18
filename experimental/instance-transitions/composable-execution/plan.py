#!/usr/bin/env python3
"""Pure capability-graph planner: no shell, UID, credentials, or target execution."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
REF = re.compile(r"(?:(did:[a-z0-9]+:[A-Za-z0-9._:%-]+)#)?(interface|module|transition)/([a-z][a-z0-9-]*)@([1-9][0-9]*)\Z")
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
METHOD = re.compile(r"[a-z][a-z0-9_]*\Z")
KEYS = ("kind", "authority", "name", "version")


def identity(doc, kind):
    if (not isinstance(doc, dict) or any(k not in doc for k in KEYS) or doc["kind"] != kind
            or not isinstance(doc["authority"], str) or not re.fullmatch(r"did:[a-z0-9]+:[A-Za-z0-9._:%-]+", doc["authority"])
            or not isinstance(doc["name"], str) or not NAME.fullmatch(doc["name"])
            or type(doc["version"]) is not int or doc["version"] < 1):
        raise ValueError(f"invalid {kind} identity: {doc!r}")
    return tuple(doc[k] for k in KEYS)


def reference(text, kind, authority=None):
    match = REF.fullmatch(text) if isinstance(text, str) else None
    if not match or match[2] != kind or not (match[1] or authority):
        raise ValueError(f"invalid or unscoped {kind} reference: {text!r}")
    return (kind, match[1] or authority, match[3], int(match[4]))


def catalog(root):
    result = {}
    for kind, pattern in (("interface", "interfaces/*.json"), ("module", "modules/*/module.json"),
                          ("transition", "transitions/*/transition.json")):
        docs = {}
        for file in sorted(root.glob(pattern)):
            doc = json.loads(file.read_text())
            key = identity(doc, kind)
            if key in docs:
                raise ValueError(f"duplicate {kind}: {key}")
            doc["_file"] = file.relative_to(root)
            docs[key] = doc
        result[kind] = docs
    interfaces, modules, transitions = (result[k] for k in ("interface", "module", "transition"))
    for key, interface in interfaces.items():
        methods = interface.get("methods")
        if not isinstance(methods, dict) or any(not isinstance(name, str) or not METHOD.fullmatch(name) for name in methods):
            raise ValueError(f"invalid interface methods: {key}")
        for name, contract in methods.items():
            if not isinstance(contract, dict):
                raise ValueError(f"invalid interface method contract: {key}.{name}")
            params = contract.get("params", [])
            if (not isinstance(params, list) or any(not isinstance(p, str) or not METHOD.fullmatch(p)
                                                     for p in params) or len(set(params)) != len(params)):
                raise ValueError(f"invalid interface method parameters: {key}.{name}")
    for key, module in modules.items():
        implemented = reference(module.get("implements"), "interface", module["authority"])
        if implemented not in interfaces:
            raise ValueError(f"unknown interface: {key}")
        required = [reference(i, "interface", module["authority"]) for i in module.get("requires", [])]
        if len(set(required)) != len(required) or any(i not in interfaces for i in required):
            raise ValueError(f"invalid module dependencies: {key}")
        if not set(reference(i, "interface", interfaces[implemented]["authority"])
                   for i in interfaces[implemented].get("requires", [])).issubset(required):
            raise ValueError(f"missing interface dependency: {key}")
        methods = module.get("methods", {})
        if set(methods) != set(interfaces[implemented]["methods"]):
            raise ValueError(f"incomplete module methods: {key}")
        for name, spec in methods.items():
            if not isinstance(spec, dict):
                raise ValueError(f"invalid method implementation: {key}.{name}")
            if spec.get("implementation") == "external":
                if set(spec) != {"implementation"} or implemented[2] != "executor":
                    raise ValueError(f"invalid external executor: {key}.{name}")
                continue
            if spec.get("implementation") == "delegate":
                via = reference(spec.get("via"), "interface", module["authority"])
                if set(spec) != {"implementation", "via"} or via not in required or via[2] != "executor":
                    raise ValueError(f"invalid runtime delegate: {key}.{name}")
                continue
            if set(spec) != {"runtime", "artifact", "format", "grant", "args"}:
                raise ValueError(f"invalid method implementation: {key}.{name}")
            runtime = reference(spec.get("runtime"), "interface", module["authority"])
            params = interfaces[implemented]["methods"][name].get("params", [])
            if (runtime not in required or not isinstance(spec.get("grant"), str) or not spec["grant"]
                    or not isinstance(spec.get("args"), list) or any(
                        not isinstance(arg, str) or not METHOD.fullmatch(arg) for arg in spec["args"])
                    or len(set(spec["args"])) != len(spec["args"])
                    or not set(params).issubset(spec["args"])):
                raise ValueError(f"unbound runtime or grant: {key}.{name}")
            relative = spec.get("artifact")
            if (not isinstance(relative, str) or not re.fullmatch(r"methods/[a-z][a-z0-9_.-]*", relative)
                    or not isinstance(spec["format"], str) or not spec["format"]):
                raise ValueError(f"invalid method artifact: {key}.{name}")
            file = root / module["_file"].parent / relative
            if not file.is_file() or file.is_symlink() or file.parent.is_symlink():
                raise ValueError(f"missing or linked method artifact: {key}.{name}")
    for key, transition in transitions.items():
        endpoint = reference(transition.get("to"), "module", transition["authority"])
        declared_interface = reference(transition.get("interface"), "interface", transition["authority"])
        if (endpoint not in modules or declared_interface not in interfaces
                or reference(modules[endpoint]["implements"], "interface", modules[endpoint]["authority"])
                != declared_interface or not isinstance(transition.get("operations"), list)):
            raise ValueError(f"invalid transition: {key}")
        if transition.get("from") is not None:
            source = reference(transition["from"], "module", transition["authority"])
            if (source not in modules or reference(modules[source]["implements"], "interface",
                                                    modules[source]["authority"]) != declared_interface):
                raise ValueError(f"invalid transition source: {key}")
        for call in transition["operations"]:
            if (not isinstance(call, dict) or not {"instance", "method"}.issubset(call)
                    or set(call) - {"instance", "method", "args"}
                    or not isinstance(call["instance"], str) or not isinstance(call["method"], str)
                    or not isinstance(call.get("args", {}), dict)):
                raise ValueError(f"invalid transition call: {key}")
    return result


def expand(root=ROOT):
    docs = catalog(root)
    instances = {}
    for file in sorted((root / "instances").glob("*.json")):
        doc = json.loads(file.read_text())
        name = doc.get("id")
        if not isinstance(name, str) or not NAME.fullmatch(name) or name != file.stem or name in instances:
            raise ValueError(f"invalid instance: {file}")
        mod_id = reference(doc.get("module"), "module")
        if (mod_id not in docs["module"] or not isinstance(doc.get("target"), str)
                or not doc["target"] or type(doc.get("provided", False)) is not bool):
            raise ValueError(f"unknown module or target: {name}")
        module = docs["module"][mod_id]
        bindings = doc.get("bindings", {})
        expected = {reference(ref, "interface", module["authority"]) for ref in module.get("requires", [])}
        if not isinstance(bindings, dict):
            raise ValueError(f"invalid bindings: {name}")
        pairs = [(reference(ref, "interface"), provider) for ref, provider in bindings.items()]
        if set(ref for ref, _ in pairs) != expected or len(pairs) != len(expected):
            raise ValueError(f"missing or duplicate bindings: {name}")
        doc["_module"] = module
        doc["_bindings"] = dict(pairs)
        instances[name] = doc
    for name, instance in instances.items():
        for iface, provider in instance["_bindings"].items():
            if provider not in instances or instances[provider]["target"] != instance["target"]:
                raise ValueError(f"unavailable or cross-target provider: {name} -> {provider}")
            bound = instances[provider]["_module"]
            if reference(bound["implements"], "interface", bound["authority"]) != iface:
                raise ValueError(f"wrong provider interface: {name} -> {provider}")
        if instance.get("provided", False):
            if (reference(instance["_module"]["implements"], "interface", instance["_module"]["authority"])
                    != reference("interface/executor@1", "interface", instance["_module"]["authority"])
                    or instance["_bindings"]):
                raise ValueError(f"only unbound bootstrap executors can be provided: {name}")
            grants = instance.get("grants")
            if (not isinstance(grants, list) or any(not isinstance(g, str) or not g for g in grants)
                    or len(grants) != len(set(grants))):
                raise ValueError(f"invalid executor grant claims: {name}")
    requested = json.loads((root / "requests.json").read_text())["transitions"]
    chosen = {}
    for entry in requested:
        if not isinstance(entry, dict) or set(entry) != {"instance", "transition"} or entry["instance"] in chosen:
            raise ValueError("invalid or duplicate request")
        key = reference(entry["transition"], "transition")
        if key not in docs["transition"]:
            raise ValueError(f"unknown requested transition: {entry}")
        chosen[entry["instance"]] = docs["transition"][key]
    if set(chosen) != {name for name, doc in instances.items() if not doc.get("provided", False)}:
        raise ValueError("every managed instance needs an explicit transition")
    for name, transition in chosen.items():
        if reference(transition["to"], "module", transition["authority"]) != identity(instances[name]["_module"], "module"):
            raise ValueError(f"requested endpoint mismatch: {name}")
    ordered, active, done = [], set(), set()
    def visit(name):
        if name in active:
            raise ValueError(f"instance dependency cycle: {name}")
        if name in done:
            return
        active.add(name)
        for provider in instances[name]["_bindings"].values():
            visit(provider)
        active.remove(name)
        done.add(name)
        if name in chosen:
            ordered.append(name)
    for name in chosen:
        visit(name)
    def reachable(start, receiver, seen=None):
        if start == receiver:
            return True
        seen = set() if seen is None else seen
        if start in seen:
            return False
        seen.add(start)
        return any(reachable(provider, receiver, seen) for provider in instances[start]["_bindings"].values())

    plan = []
    for name in ordered:
        transition = chosen[name]
        calls = []
        for operation in transition["operations"]:
            receiver_name = operation["instance"]
            if receiver_name not in instances or not reachable(name, receiver_name):
                raise ValueError(f"unbound method receiver: {name} -> {receiver_name}")
            receiver = instances[receiver_name]
            method = receiver["_module"]["methods"].get(operation["method"])
            if method is None or method.get("implementation") in ("external", "delegate"):
                raise ValueError(f"unknown or non-artifact instance method: {receiver_name}.{operation['method']}")
            interface_key = reference(receiver["_module"]["implements"], "interface",
                                      receiver["_module"]["authority"])
            params = docs["interface"][interface_key]["methods"][operation["method"]].get("params", [])
            supplied = operation.get("args", {})
            if set(supplied) != set(params) or any(not isinstance(value, str) for value in supplied.values()):
                raise ValueError(f"invalid method call arguments: {receiver_name}.{operation['method']}")
            runtime_iface = reference(method["runtime"], "interface", receiver["_module"]["authority"])
            if runtime_iface not in receiver["_bindings"]:
                raise ValueError(f"method runtime not bound: {receiver_name}.{operation['method']}")
            runtime_name = receiver["_bindings"][runtime_iface]
            runtime = instances[runtime_name]
            if method["format"] not in runtime["_module"].get("accepts", []):
                raise ValueError(f"runtime rejects artifact format: {runtime_name}")
            executor_iface = reference("interface/executor@1", "interface", runtime["_module"]["authority"])
            if executor_iface not in runtime["_bindings"]:
                raise ValueError(f"runtime lacks executor: {runtime_name}")
            executor_name = runtime["_bindings"][executor_iface]
            executor = instances[executor_name]
            if (receiver["target"] != instances[name]["target"] or not executor.get("provided", False)
                    or method["grant"] not in executor.get("grants", [])):
                raise ValueError(f"unauthorized or cross-target invocation: {receiver_name}.{operation['method']}")
            inputs = receiver.get("inputs", {})
            if (not isinstance(inputs, dict) or any(arg not in inputs and arg not in supplied
                                                    for arg in method["args"])
                    or any(not isinstance((supplied if arg in supplied else inputs)[arg], str)
                           for arg in method["args"])):
                raise ValueError(f"missing or invalid method inputs: {receiver_name}.{operation['method']}")
            calls.append({"receiver": receiver_name, "method": operation["method"],
                          "args": [(supplied if arg in supplied else inputs)[arg] for arg in method["args"]],
                          "artifact": str(receiver["_module"]["_file"].parent / method["artifact"]),
                          "runtime": runtime_name, "format": method["format"],
                          "executable": runtime["_module"].get("executable"),
                          "executor": executor_name, "target": receiver["target"],
                          "grant": method["grant"]})
        plan.append({"instance": name, "transition": transition["name"], "calls": calls})
    return plan


if __name__ == "__main__":
    try:
        if sys.argv[1:] != ["--expand"]:
            raise ValueError("usage: python3 plan.py --expand")
        print(json.dumps(expand(), indent=2))
    except (ValueError, KeyError, OSError, TypeError, json.JSONDecodeError) as exc:
        print(f"plan: {exc}", file=sys.stderr)
        sys.exit(1)
