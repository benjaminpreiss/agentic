import json
import tempfile
import unittest
from pathlib import Path
from plan import plan


class PlannerTests(unittest.TestCase):
    def test_repo_inventory_is_ordered(self):
        ordered = plan(Path(__file__).resolve().parent / "modules")
        positions = {module["id"]: i for i, module in enumerate(ordered)}
        self.assertEqual(len(positions), len(ordered))
        for module in ordered:
            for dep in module["requires"]:
                self.assertLess(positions[dep], positions[module["id"]])

    def test_missing_and_cyclic_dependencies_fail_closed(self):
        with tempfile.TemporaryDirectory() as tmp:
            file = Path(tmp) / "a.json"
            module = {"id": "a", "version": "1", "substrate": "test", "status": "test", "requires": ["missing"]}
            file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, "missing dependency"):
                plan(Path(tmp))
            module["requires"] = ["a"]
            file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, "dependency cycle"):
                plan(Path(tmp))


if __name__ == "__main__":
    unittest.main()
