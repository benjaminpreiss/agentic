#!/usr/bin/env python3
"""Pure expansion of bound Python instances; explicit rendering, never remote execution."""
from dataclasses import dataclass
import json
from pathlib import Path
import re
import shlex
import sys
from typing import Sequence

from deployment import Instance
from interfaces_v1 import Module, Target

ROOT = Path(__file__).resolve().parent
SCRIPTS = ROOT / "scripts"
IDENTIFIER = re.compile(r"[a-z][a-z0-9-]*\Z")
@dataclass(frozen=True)
class Task:
    instance: str
    module: str
    dependencies: tuple[str, ...]
    script: Path
    args: tuple[str, ...]


class Recorder(Target):
    """A non-executing Target: module.ensure() can only declare a task here."""

    def __init__(self, instance: Instance[Module], dependencies: tuple[str, ...]):
        self.instance = instance
        self.dependencies = dependencies
        self.tasks: list[Task] = []

    def run(self, script: Path, args: tuple[str, ...] = ()) -> None:
        resolved = script.resolve()
        if (not resolved.is_relative_to(SCRIPTS) or resolved.suffix != ".sh" or not resolved.is_file()
                or not all(isinstance(arg, str) for arg in args)):
            raise ValueError(f"invalid implementation script or arguments: {self.instance.name}")
        self.tasks.append(Task(self.instance.name, type(self.instance.module).__name__,
                               self.dependencies, resolved, args))


def expand(instances: Sequence[Instance[Module]]) -> list[Task]:
    """Resolve Python object bindings by identity without contacting a target."""
    by_object: dict[int, Instance[Module]] = {}
    names: set[str] = set()
    for instance in instances:
        if (not IDENTIFIER.fullmatch(instance.name) or instance.name in names
                or id(instance.module) in by_object):
            raise ValueError(f"duplicate or invalid instance: {instance.name}")
        names.add(instance.name)
        by_object[id(instance.module)] = instance

    ordered: list[Instance[Module]] = []
    active: set[int] = set()
    done: set[int] = set()

    def visit(instance: Instance[Module]) -> None:
        identity = id(instance.module)
        if identity in active:
            raise ValueError(f"dependency cycle: {instance.name}")
        if identity in done:
            return
        active.add(identity)
        for dependency in instance.module.dependencies():
            provider = by_object.get(id(dependency))
            if provider is None:
                raise ValueError(f"unbound dependency: {instance.name}")
            visit(provider)
        active.remove(identity)
        done.add(identity)
        ordered.append(instance)

    for instance in instances:
        visit(instance)
    tasks: list[Task] = []
    for instance in ordered:
        dependencies = tuple(by_object[id(dep)].name for dep in instance.module.dependencies())
        recorder = Recorder(instance, dependencies)
        instance.module.ensure(recorder)
        if not recorder.tasks:
            raise ValueError(f"no ensure task: {instance.name}")
        tasks.extend(recorder.tasks)
    return tasks


def render(tasks: Sequence[Task]) -> str:
    """Render a script for manual SSH execution on a disposable target."""
    lines = ["#!/bin/sh", "set -eu",
             "[ \"${AGENTIC_DISPOSABLE_VM:-}\" = true ] && [ \"${AGENTIC_CONSOLE_VERIFIED:-}\" = true ] || { echo 'Disposable VM and console confirmation required' >&2; exit 1; }",
             "[ \"$(id -u)\" -eq 0 ] || { echo 'Run as root on the target' >&2; exit 1; }"]
    for index, task in enumerate(tasks):
        delimiter = f"AGENTIC_TASK_{index}"
        content = task.script.read_text()
        if delimiter in content:
            raise ValueError("script contains its here-document delimiter")
        args = " ".join(shlex.quote(arg) for arg in task.args)
        lines.extend([f"# {task.instance}: {task.module} (after {', '.join(task.dependencies)})",
                      f"sh -s -- {args} <<'{delimiter}'", content.rstrip("\n"), delimiter])
    return "\n".join(lines) + "\n"


if __name__ == "__main__":
    from instances import DEPLOYMENT

    try:
        tasks = expand(DEPLOYMENT)
        if sys.argv[1:] == ["--expand"]:
            print(json.dumps([{"instance": t.instance, "module": t.module,
                               "dependencies": t.dependencies, "script": str(t.script.relative_to(ROOT)),
                               "args": t.args} for t in tasks], indent=2))
        elif sys.argv[1:] == ["--script"]:
            print(render(tasks), end="")
        else:
            raise ValueError("usage: plan.py [--expand | --script]")
    except (OSError, ValueError, TypeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
