import json
import subprocess
import sys
import tempfile
import unittest
from pathlib import Path
from plan import plan, playbook


class PlannerTests(unittest.TestCase):
    def test_repo_inventory_is_ordered(self):
        ordered = plan(Path(__file__).resolve().parent / "modules")
        positions = {module["id"]: i for i, module in enumerate(ordered)}
        self.assertEqual(len(positions), len(ordered))
        rendered = playbook(ordered)
        for module in ordered:
            self.assertIn(f"modules/{module['id']}/introduce.yml", rendered)
            for dep in module["requires"]:
                self.assertLess(positions[dep], positions[module["id"]])

    def test_generated_subset_contains_only_dependency_closure(self):
        root = Path(__file__).resolve().parent
        output = subprocess.check_output([sys.executable, str(root / "plan.py"), "--until", "base-access"], text=True)
        self.assertIn("modules/opensuse-tumbleweed/introduce.yml", output)
        self.assertIn("modules/hardware-inventory/introduce.yml", output)
        self.assertIn("modules/base-access/introduce.yml", output)
        self.assertNotIn("modules/nix-packages/introduce.yml", output)
        self.assertNotIn("modules/firstboot-diagnostics/introduce.yml", output)

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
