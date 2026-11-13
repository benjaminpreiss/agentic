import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from plan import closure, plan, playbook


class PlannerTests(unittest.TestCase):
    def test_repo_inventory_is_ordered(self):
        ordered = plan(Path(__file__).resolve().parent / "modules")
        positions = {module["id"]: i for i, module in enumerate(ordered)}
        self.assertEqual(len(positions), len(ordered))
        rendered = playbook(ordered)
        for module in ordered:
            self.assertIn(f"modules/{module['id']}/introduce.yml", rendered)
            for dep in module["_dependencies"]:
                self.assertLess(positions[dep], positions[module["id"]])
        self.assertLess(positions["systemd-timer"], positions["home-backup"])
        self.assertIn("modules/systemd-timer/ensure.yml", rendered)
        self.assertIn('timer_schedule: "*-*-* 03:30:00"', rendered)
        self.assertNotIn("modules/home-backup/agentic-backup.timer", rendered)
        subset = playbook(closure(ordered, "home-backup"))
        self.assertIn("modules/systemd-timer/introduce.yml", subset)
        self.assertNotIn("modules/github-integration/introduce.yml", subset)

    def test_generated_subset_contains_only_dependency_closure(self):
        root = Path(__file__).resolve().parent
        output = subprocess.check_output([sys.executable, str(root / "plan.py"), "--until", "base-access"], text=True)
        self.assertIn("modules/opensuse-tumbleweed/introduce.yml", output)
        self.assertIn("modules/hardware-inventory/introduce.yml", output)
        self.assertIn("modules/base-access/introduce.yml", output)
        self.assertNotIn("modules/nix-packages/introduce.yml", output)
        self.assertNotIn("modules/firstboot-diagnostics/introduce.yml", output)

    def test_interface_signatures_and_bindings_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            (root / "interfaces").mkdir()
            (root / "modules" / "provider").mkdir(parents=True)
            (root / "modules" / "caller").mkdir()
            (root / "interfaces" / "timer.v1.json").write_text(json.dumps({
                "id": "timer", "version": 1, "operations": {"ensure": {"args": {"id": "string"}}}}))
            (root / "bindings.json").write_text('{"timer@1":"provider"}')
            provider = {"id": "provider", "version": "1", "substrate": "x", "status": "x", "requires": [],
                        "provides": {"timer@1": {"ensure": "ensure.yml"}}}
            caller = {"id": "caller", "version": "1", "substrate": "x", "status": "x", "requires": [],
                      "requires_interfaces": ["timer@1"], "calls": [{"interface": "timer@1", "operation": "ensure", "args": {"id": "test"}}]}
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
            (root / "modules" / "caller" / "module.json").write_text(json.dumps(caller))
            (root / "bindings.json").write_text('{"timer@1":"other"}')
            with self.assertRaisesRegex(ValueError, "missing provider"):
                plan(root / "modules")

    def test_missing_and_cyclic_dependencies_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp) / "a"
            folder.mkdir()
            file = folder / "module.json"
            (folder / "introduce.yml").write_text("---\n[]\n")
            module = {"id": "a", "version": "1", "substrate": "test", "status": "test", "requires": ["missing"]}
            file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, "missing dependency"):
                plan(Path(tmp))
            module["requires"] = ["a"]
            file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, "dependency cycle"):
                plan(Path(tmp))
            (folder / "introduce.yml").unlink()
            with self.assertRaisesRegex(ValueError, "missing introduction script"):
                plan(Path(tmp))


if __name__ == "__main__":
    unittest.main()
