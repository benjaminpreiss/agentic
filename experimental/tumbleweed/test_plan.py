import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from plan import closure, plan, playbook

ROOT = Path(__file__).resolve().parent


class PlannerTests(unittest.TestCase):
    def test_all_contracts_are_local_and_dependencies_ordered(self):
        ordered = plan(ROOT / "modules")
        positions = {module["id"]: i for i, module in enumerate(ordered)}
        self.assertEqual(len(positions), 11)
        rendered = playbook(ordered)
        for module in ordered:
            self.assertNotIn("requires", module)
            self.assertIn("provides", module)
            for requirement in module["requires_interfaces"]:
                self.assertIn("operations", requirement)
            for provider in module["_dependencies"]:
                self.assertLess(positions[provider], positions[module["id"]])
        self.assertIn("modules/systemd-timer/ensure.yml", rendered)
        self.assertIn('timer_schedule: "*-*-* 03:30:00"', rendered)
        subset = playbook(closure(ordered, "home-backup"))
        self.assertIn("modules/systemd-timer/introduce.yml", subset)
        self.assertNotIn("modules/github-integration/introduce.yml", subset)

    def test_base_access_closure(self):
        output = subprocess.check_output([sys.executable, str(ROOT / "plan.py"), "--until", "base-access"], text=True)
        for name in ("opensuse-tumbleweed", "hardware-inventory", "base-access"):
            self.assertIn(f"modules/{name}/introduce.yml", output)
        self.assertNotIn("modules/nix-packages/introduce.yml", output)

    def test_mismatched_consumer_signature_and_missing_binding_fail(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for name in ("provider", "caller"):
                (root / "modules" / name).mkdir(parents=True)
                (root / "modules" / name / "introduce.yml").write_text("---\n[]\n")
            (root / "modules" / "provider" / "run.yml").write_text("---\n[]\n")
            (root / "bindings.json").write_text('{"timer@1":"provider","caller@1":"caller"}')
            provider = {"id": "provider", "version": "1", "substrate": "native", "status": "x",
                        "requires_interfaces": [], "implements": "timer@1", "entrypoint": "prepare",
                        "provides": {"timer@1": {"prepare": {"args": {}, "script": "introduce.yml"},
                                                 "ensure": {"args": {"id": "string"}, "script": "run.yml"}}}}
            caller = {"id": "caller", "version": "1", "substrate": "native", "status": "x",
                      "requires_interfaces": [{"interface": "timer@1", "operations": {"ensure": {"args": {"id": "string"}}}}],
                      "implements": "caller@1", "entrypoint": "ensure",
                      "provides": {"caller@1": {"ensure": {"args": {}, "script": "introduce.yml"}}},
                      "calls": [{"interface": "timer@1", "operation": "ensure", "args": {"id": "sample"}}]}
            provider_file = root / "modules" / "provider" / "module.json"
            caller_file = root / "modules" / "caller" / "module.json"
            provider_file.write_text(json.dumps(provider))
            caller_file.write_text(json.dumps(caller))
            self.assertIn("modules/provider/run.yml", playbook(plan(root / "modules")))
            caller["requires_interfaces"][0]["operations"]["ensure"]["args"]["id"] = "integer"
            caller_file.write_text(json.dumps(caller))
            with self.assertRaisesRegex(ValueError, "incompatible interface method"):
                plan(root / "modules")
            caller["requires_interfaces"][0]["operations"]["ensure"]["args"]["id"] = "string"
            caller_file.write_text(json.dumps(caller))
            (root / "bindings.json").write_text('{"caller@1":"caller"}')
            with self.assertRaisesRegex(ValueError, "unbound implementation"):
                plan(root / "modules")
            (root / "bindings.json").write_text('{"timer@1":"provider","caller@1":"caller"}')
            caller["requires"] = ["provider"]
            caller_file.write_text(json.dumps(caller))
            with self.assertRaisesRegex(ValueError, "concrete module dependencies"):
                plan(root / "modules")


if __name__ == "__main__":
    unittest.main()
