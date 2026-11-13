#!/usr/bin/env python3
"""Experimental planner: local interfaces, bound instances and runtime outputs."""
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


def key(interface, instance):
    if not isinstance(interface, str) or not INTERFACE.fullmatch(interface) or not isinstance(instance, str) or not NAME.fullmatch(instance):
        raise ValueError(f"invalid interface instance: {interface}#{instance}")
    return f"{interface}#{instance}"


def plan(root=ROOT):
    bindings = json.loads((root / "bindings.json").read_text())
    modules = {}
    for file in sorted((root / "modules").glob("*/module.json")):
        module = json.loads(file.read_text())
        identifier = module["id"]
        if not isinstance(identifier, str) or not NAME.fullmatch(identifier) or identifier != file.parent.name or identifier in modules:
            raise ValueError(f"invalid or duplicate module: {file}")
        contract = key(module["implements"], module["instance"])
        if bindings.get(contract) != identifier:
            raise ValueError(f"missing binding for implementation: {contract}")
        operations = module["provides"].get(module["implements"])
        if not isinstance(operations, dict) or not operations:
            raise ValueError(f"module does not describe provided interface: {identifier}")
        for name, operation in operations.items():
            script = operation.get("script")
            if not NAME.fullmatch(name) or not valid_signature(operation.get("args")) or not valid_signature(operation.get("outputs")):
                raise ValueError(f"invalid provided method: {identifier}.{name}")
            if not isinstance(script, str) or not SCRIPT.fullmatch(script) or not (file.parent / script).is_file():
                raise ValueError(f"missing operation script: {identifier}.{name}")
        entrypoint = operations.get(module["entrypoint"])
        if entrypoint is None or entrypoint["args"]:
            raise ValueError(f"entrypoint must take no public arguments: {identifier}")
        modules[identifier] = module

    for binding, identifier in bindings.items():
        if identifier not in modules or key(modules[identifier]["implements"], modules[identifier]["instance"]) != binding:
            raise ValueError(f"invalid binding: {binding} -> {identifier}")

    for identifier, module in modules.items():
        required = {}
        dependencies = []
        for requirement in module["requires"]:
            bound = key(requirement["interface"], requirement["instance"])
            if bound in required or bound not in bindings:
                raise ValueError(f"duplicate or unbound requirement: {identifier} -> {bound}")
            provider = modules[bindings[bound]]
            expected = requirement["methods"]
            actual = provider["provides"][requirement["interface"]]
            if not isinstance(expected, dict) or not expected:
                raise ValueError(f"empty required interface: {identifier} -> {bound}")
            for name, signature in expected.items():
                method = actual.get(name)
                if method is None or not valid_signature(signature.get("args")) or not valid_signature(signature.get("outputs")):
                    raise ValueError(f"invalid method requirement: {identifier} -> {bound}.{name}")
                if signature["args"] != method["args"] or any(method["outputs"].get(output) != typ for output, typ in signature["outputs"].items()):
                    raise ValueError(f"incompatible method: {identifier} -> {bound}.{name}")
            required[bound] = expected
            dependencies.append(provider["id"])
        inputs = module.get("inputs", {})
        if not isinstance(inputs, dict) or any(not ARG.fullmatch(name) for name in inputs):
            raise ValueError(f"invalid inputs: {identifier}")
        for name, input_spec in inputs.items():
            source = input_spec["from"]
            bound = key(source["interface"], source["instance"])
            method = required.get(bound, {}).get(source["method"], {})
            output_type = method.get("outputs", {}).get(source["output"])
            if output_type != input_spec["type"] or input_spec["type"] != "string":
                raise ValueError(f"unavailable or incompatible output: {identifier}.{name}")
        module["_dependencies"] = dependencies

    ordered, active, done = [], set(), set()
    def visit(identifier):
        if identifier in active:
            raise ValueError(f"dependency cycle: {identifier}")
        if identifier in done:
            return
        active.add(identifier)
        for dep in modules[identifier]["_dependencies"]:
            visit(dep)
        active.remove(identifier)
        done.add(identifier)
        ordered.append(modules[identifier])
    for identifier in modules:
        visit(identifier)
    return ordered


def playbook(ordered):
    lines = ["---", "- name: Experiment with module outputs on a disposable Tumbleweed VM",
             "  hosts: agentic_vm", "  gather_facts: true", "  become: true",
             "  pre_tasks:", "    - name: Discard results from any previous run",
             "      ansible.builtin.set_fact:", "        deployment_results: {}", "  tasks:"]
    for module in ordered:
        operation = module["provides"][module["implements"]][module["entrypoint"]]
        bound = key(module["implements"], module["instance"])
        lines += [f"    - name: Ensure {bound}",
                  f"      ansible.builtin.import_tasks: modules/{module['id']}/{operation['script']}",
                  "      vars:", f"        module_result_key: {json.dumps(bound)}"]
        for name, input_spec in module.get("inputs", {}).items():
            source = input_spec["from"]
            result_key = key(source["interface"], source["instance"])
            expr = f"{{{{ deployment_results[{result_key!r}][{source['output']!r}] }}}}"
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
            for module in ordered:
                print(key(module["implements"], module["instance"]))
        else:
            raise ValueError("usage: plan.py [--playbook]")
    except (OSError, ValueError, KeyError, TypeError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
