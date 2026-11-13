#!/usr/bin/env python3
"""Prototype dependency planner. Never changes the host."""
import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent


def plan(directory: Path):
    modules = {}
    for path in sorted(directory.glob("*.json")):
        module = json.loads(path.read_text())
        key = module["id"]
        if key in modules:
            raise ValueError(f"duplicate module {key}")
        if not all(isinstance(module.get(field), str) for field in ("id", "version", "substrate", "status")):
            raise ValueError(f"invalid module: {path}")
        if not isinstance(module.get("requires"), list):
            raise ValueError(f"invalid dependencies: {path}")
        modules[key] = module

    ordered = []
    visiting = set()
    visited = set()

    def visit(key):
        if key not in modules:
            raise ValueError(f"missing dependency: {key}")
        if key in visiting:
            raise ValueError(f"dependency cycle at {key}")
        if key in visited:
            return
        visiting.add(key)
        for dep in modules[key]["requires"]:
            visit(dep)
        visiting.remove(key)
        visited.add(key)
        ordered.append(modules[key])

    for key in modules:
        visit(key)
    return ordered


if __name__ == "__main__":
    try:
        for module in plan(Path(sys.argv[1]) if len(sys.argv) > 1 else ROOT / "modules"):
            print(f'{module["id"]}@{module["version"]} [{module["substrate"]}] {module["status"]}')
    except (ValueError, OSError, json.JSONDecodeError) as error:
        print(f"plan: {error}", file=sys.stderr)
        sys.exit(1)
