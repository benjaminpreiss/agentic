#!/usr/bin/env python3
"""Experimental instance planner: shared contracts, bindings and runtime outputs."""
import json
import re
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent
NAME = re.compile(r"[a-z][a-z0-9-]*\Z")
INTERFACE = re.compile(r"[a-z][a-z0-9-]*@[1-9][0-9]*\Z")
SCRIPT = re.compile(r"[a-z][a-z0-9-]*\.yml\Z")
ARG = re.compile(r"[a-z][a-z0-9_]*\Z")


def valid_signature(signature):
    return isinstance(signature, dict) and all(ARG.fullmatch(k) and v == "string" for k, v in signature.items())


def result_key(interface, instance):
    return f"{interface}#{instance}"


def plan(root=ROOT):
    interfaces = {}
    for file in sorted((root / "interfaces").glob("*.json")):
        contract = json.loads(file.read_text())
        identifier = contract["id"]
        if not isinstance(identifier, str) or not INTERFACE.fullmatch(identifier):
            raise ValueError(f"invalid interface: {file}")
        name, version = identifier.rsplit("@", 1)
        if file.name != f"{name}.v{version}.json" or identifier in interfaces:
            raise ValueError(f"invalid or duplicate interface: {file}")
        methods = contract.get("methods")
        if not isinstance(methods, dict) or not methods:
            raise ValueError(f"interface has no methods: {identifier}")
        for method, signature in methods.items():
            if (not NAME.fullmatch(method) or not isinstance(signature, dict)
                    or not valid_signature(signature.get("args"))
                    or not valid_signature(signature.get("outputs"))
                    or not isinstance(signature.get("guarantee"), str) or not signature["guarantee"]):
                raise ValueError(f"invalid interface method: {identifier}.{method}")
        interfaces[identifier] = contract
    modules = {}
    for file in sorted((root / "modules").glob("*/module.json")):
        module = json.loads(file.read_text())
        identifier = module["id"]
        if not NAME.fullmatch(identifier) or identifier != file.parent.name or identifier in modules:
            raise ValueError(f"invalid or duplicate module: {file}")
        interface = module["implements"]
        if interface not in interfaces:
            raise ValueError(f"unknown provided interface: {identifier} -> {interface}")
        operations = module.get("operations")
        methods = interfaces[interface]["methods"]
        if not isinstance(operations, dict) or set(operations) != set(methods):
            raise ValueError(f"module must implement every method of {interface}: {identifier}")
        for name, script in operations.items():
            if not isinstance(script, str) or not SCRIPT.fullmatch(script) or not (file.parent / script).is_file():
                raise ValueError(f"missing operation script: {identifier}.{name}")
        entrypoint = methods.get(module["entrypoint"])
        if entrypoint is None or entrypoint["args"]:
            raise ValueError(f"entrypoint must take no public arguments: {identifier}")
        if not isinstance(module.get("requires"), list) or len(module["requires"]) != len(set(module["requires"])):
            raise ValueError(f"invalid required interfaces: {identifier}")
        for required in module["requires"]:
            if not isinstance(required, str) or required not in interfaces:
                raise ValueError(f"unknown required interface: {identifier} -> {required}")
        inputs = module.get("inputs", {})
        if not isinstance(inputs, dict) or any(not ARG.fullmatch(name) or not isinstance(spec, dict) or spec.get("type") != "string" for name, spec in inputs.items()):
            raise ValueError(f"invalid input declarations: {identifier}")
        module["_contract"] = interfaces[interface]
        modules[identifier] = module

    instances = {}
    for file in sorted((root / "instances").glob("*.json")):
        instance = json.loads(file.read_text())
        identifier = instance["id"]
        if not NAME.fullmatch(identifier) or file.stem != identifier or identifier in instances:
            raise ValueError(f"invalid or duplicate instance: {file}")
        module_name = instance["module"]
        if module_name not in modules:
            raise ValueError(f"unknown module for instance {identifier}: {module_name}")
        instance["_module"] = modules[module_name]
        instances[identifier] = instance

    for identifier, instance in instances.items():
        module = instance["_module"]
        required = {}
        dependencies = []
        bindings = instance.get("bindings", {})
        if not isinstance(bindings, dict):
            raise ValueError(f"invalid bindings for {identifier}")
        for interface in module["requires"]:
            if interface not in bindings:
                raise ValueError(f"missing binding: {identifier} -> {interface}")
            provider_id = bindings[interface]
            if provider_id not in instances or provider_id == identifier:
                raise ValueError(f"unknown or self provider: {identifier} -> {provider_id}")
            provider = instances[provider_id]["_module"]
            if provider["implements"] != interface:
                raise ValueError(f"binding does not provide {interface}: {identifier} -> {provider_id}")
            required[interface] = interfaces[interface]["methods"]
            dependencies.append(provider_id)
        if set(bindings) != set(required):
            raise ValueError(f"unused binding on {identifier}")
        literal_inputs = instance.get("inputs", {})
        input_specs = module.get("inputs", {})
        if not isinstance(literal_inputs, dict) or set(literal_inputs) != {name for name, spec in input_specs.items() if spec.get("source") == "config"}:
            raise ValueError(f"missing or unexpected instance input: {identifier}")
        resolved_inputs = {}
        for name, spec in input_specs.items():
            if spec.get("source") == "config":
                value = literal_inputs[name]
                if not isinstance(value, str):
                    raise ValueError(f"invalid instance input type: {identifier}.{name}")
                resolved_inputs[name] = ("literal", value)
            else:
                source = spec.get("from", {})
                interface, method_name, output = source.get("interface"), source.get("method"), source.get("output")
                declared = required.get(interface, {}).get(method_name, {})
                provider = instances[bindings[interface]]["_module"] if interface in bindings else None
                if (declared.get("outputs", {}).get(output) != spec["type"]
                        or provider is None or method_name != provider["entrypoint"]):
                    raise ValueError(f"unavailable or incompatible output: {identifier}.{name}")
                resolved_inputs[name] = ("output", result_key(interface, bindings[interface]), output)
        instance["_dependencies"] = dependencies
        instance["_inputs"] = resolved_inputs

    ordered, active, done = [], set(), set()
    def visit(identifier):
        if identifier in active:
            raise ValueError(f"dependency cycle: {identifier}")
        if identifier in done:
            return
        active.add(identifier)
        for dep in instances[identifier]["_dependencies"]:
            visit(dep)
        active.remove(identifier)
        done.add(identifier)
        ordered.append(instances[identifier])
    for identifier in instances:
        visit(identifier)
    return ordered


def playbook(ordered):
    lines = ["---", "- name: Experiment with reusable modules on a disposable Tumbleweed VM",
             "  hosts: agentic_vm", "  gather_facts: true", "  become: true",
             "  pre_tasks:", "    - name: Discard results from any previous run",
             "      ansible.builtin.set_fact:", "        deployment_results: {}", "  tasks:"]
    for instance in ordered:
        module = instance["_module"]
        interface = module["implements"]
        operation = module["_contract"]["methods"][module["entrypoint"]]
        bound = result_key(interface, instance["id"])
        lines += [f"    - name: Ensure {bound} via {module['id']}",
                  f"      ansible.builtin.import_tasks: modules/{module['id']}/{module['operations'][module['entrypoint']]}",
                  "      vars:", f"        module_result_key: {json.dumps(bound)}"]
        for name, value in instance["_inputs"].items():
            if value[0] == "literal":
                lines.append(f"        {name}: {json.dumps(value[1])}")
            else:
                expr = f"{{{{ deployment_results[{value[1]!r}][{value[2]!r}] }}}}"
                lines.append(f"        {name}: {json.dumps(expr)}")
        for output in operation["outputs"]:
            reference = f"deployment_results[{bound!r}][{output!r}]"
            lines += [f"    - name: Verify {bound} returned {output}",
                      "      ansible.builtin.assert:", "        that:",
                      "          - deployment_results is defined",
                      f"          - {json.dumps(f'{bound!r} in deployment_results')}",
                      f"          - {json.dumps(f'{output!r} in deployment_results[{bound!r}]')}",
                      f"          - {json.dumps(f'{reference} is string')}"]
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    try:
        ordered = plan()
        if sys.argv[1:] == ["--playbook"]:
            print(playbook(ordered), end="")
        elif not sys.argv[1:]:
            for instance in ordered:
                print(result_key(instance["_module"]["implements"], instance["id"]))
        else:
            raise ValueError("usage: plan.py [--playbook]")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
