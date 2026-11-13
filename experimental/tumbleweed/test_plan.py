import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from plan import closure, plan, playbook

ROOT = Path(__file__).resolve().parent


class PlannerTests(unittest.TestCase):
    def test_every_module_is_bound_and_only_requires_interfaces(self):
        ordered = plan(ROOT / "modules")
        positions = {module["id"]: i for i, module in enumerate(ordered)}
        bindings = json.loads((ROOT / "bindings.json").read_text())
        self.assertEqual(len(positions), len(ordered))
        rendered = playbook(ordered)
        for module in ordered:
            self.assertNotIn("requires", module)
            self.assertEqual(bindings[module["implements"]], module["id"])
            self.assertIn(f"modules/{module['id']}/introduce.yml", rendered)
            for dep in module["_dependencies"]:
                self.assertLess(positions[dep], positions[module["id"]])
        self.assertIn("modules/systemd-timer/ensure.yml", rendered)
        self.assertIn('timer_schedule: "*-*-* 03:30:00"', rendered)
        self.assertNotIn("modules/home-backup/agentic-backup.timer", rendered)
        subset = playbook(closure(ordered, "home-backup"))
        self.assertIn("modules/systemd-timer/introduce.yml", subset)
        self.assertNotIn("modules/github-integration/introduce.yml", subset)

    def test_base_access_closure(self):
        output = subprocess.check_output([sys.executable, str(ROOT / "plan.py"), "--until", "base-access"], text=True)
        for name in ("opensuse-tumbleweed", "hardware-inventory", "base-access"):
            self.assertIn(f"modules/{name}/introduce.yml", output)
        self.assertNotIn("modules/nix-packages/introduce.yml", output)
        self.assertNotIn("modules/firstboot-diagnostics/introduce.yml", output)

    def test_invalid_signature_binding_and_legacy_dependency_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "interfaces").mkdir()
            (root / "modules" / "provider").mkdir(parents=True)
            (root / "modules" / "caller").mkdir()
            for name in ("timer", "caller"):
                (root / "interfaces" / f"{name}.v1.json").write_text(json.dumps({
                    "id": name, "version": 1, "operations": {
                        "prepare" if name == "timer" else "ensure": {"args": {}},
                        **({"ensure": {"args": {"id": "string"}}} if name == "timer" else {})}}))
            (root / "bindings.json").write_text('{"timer@1":"provider","caller@1":"caller"}')
            provider = {"id": "provider", "version": "1", "substrate": "native", "status": "x",
                        "requires_interfaces": [], "implements": "timer@1", "entrypoint": "prepare",
                        "provides": {"timer@1": {"prepare": "introduce.yml", "ensure": "ensure.yml"}}}
            caller = {"id": "caller", "version": "1", "substrate": "native", "status": "x",
                      "requires_interfaces": ["timer@1"], "implements": "caller@1", "entrypoint": "ensure",
                      "provides": {"caller@1": {"ensure": "introduce.yml"}},
                      "calls": [{"interface": "timer@1", "operation": "ensure", "args": {"id": "test"}}]}
            for name, module in [("provider", provider), ("caller", caller)]:
                (root / "modules" / name / "module.json").write_text(json.dumps(module))
                (root / "modules" / name / "introduce.yml").write_text("---\n[]\n")
            (root / "modules" / "provider" / "ensure.yml").write_text("---\n[]\n")
            self.assertIn("modules/provider/ensure.yml", playbook(plan(root / "modules")))
            caller["calls"][0]["args"] = {"id": "test", "unknown": "bad"}
            (root / "modules" / "caller" / "module.json").write_text(json.dumps(caller))
            with self.assertRaisesRegex(ValueError, "signature mismatch"):
                plan(root / "modules")
            caller["calls"][0]["args"] = {"id": "test"}
            caller["requires"] = ["provider"]
            (root / "modules" / "caller" / "module.json").write_text(json.dumps(caller))
            with self.assertRaisesRegex(ValueError, "concrete module dependencies"):
                plan(root / "modules")
            caller.pop("requires")
            (root / "modules" / "caller" / "module.json").write_text(json.dumps(caller))
            (root / "bindings.json").write_text('{"timer@1":"other","caller@1":"caller"}')
            with self.assertRaisesRegex(ValueError, "missing provider"):
                plan(root / "modules")

    def test_interface_cycle_and_missing_script_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "interfaces").mkdir()
            (root / "modules" / "a").mkdir(parents=True)
            (root / "interfaces" / "a.v1.json").write_text('{"id":"a","version":1,"operations":{"ensure":{"args":{}}}}')
            (root / "bindings.json").write_text('{"a@1":"a"}')
            module = {"id": "a", "version": "1", "substrate": "native", "status": "x",
                      "requires_interfaces": ["a@1"], "implements": "a@1", "entrypoint": "ensure",
                      "provides": {"a@1": {"ensure": "introduce.yml"}}}
            file = root / "modules" / "a" / "module.json"
            file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, "missing introduction script"):
                plan(root / "modules")
            (file.parent / "introduce.yml").write_text("---\n[]\n")
            with self.assertRaisesRegex(ValueError, "cannot depend on itself"):
                plan(root / "modules")


if __name__ == "__main__":
    unittest.main()
