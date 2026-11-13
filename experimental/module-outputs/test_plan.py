import copy
import json
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, plan, playbook


class OutputContractTests(unittest.TestCase):
    def test_verified_output_is_bound_to_account_input(self):
        ordered = plan()
        self.assertEqual([module['id'] for module in ordered], ['opensuse-tumbleweed', 'zsh', 'agentic-account'])
        rendered = playbook(ordered)
        self.assertIn("deployment_results['login-shell@1#interactive']['path']", rendered)
        self.assertIn('shell_path: "{{ deployment_results[', rendered)
        self.assertLess(rendered.index('modules/zsh/ensure.yml'), rendered.index('modules/agentic-account/ensure.yml'))
        account = (ROOT / 'modules/agentic-account/ensure.yml').read_text()
        self.assertNotIn('/bin/zsh', account)
        self.assertIn('shell: \'{{ shell_path }}\'', account)

    def test_contract_mismatch_or_unbound_instance_fails_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'modules').mkdir()
            for file in (ROOT / 'modules').glob('*/module.json'):
                folder = root / 'modules' / file.parent.name
                folder.mkdir()
                (folder / 'module.json').write_text(file.read_text())
                for script in file.parent.glob('*.yml'):
                    (folder / script.name).write_text(script.read_text())
            bindings = json.loads((ROOT / 'bindings.json').read_text())
            (root / 'bindings.json').write_text(json.dumps(bindings))
            self.assertEqual(len(plan(root)), 3)
            account_file = root / 'modules/agentic-account/module.json'
            original = json.loads(account_file.read_text())
            modified = copy.deepcopy(original)
            modified['requires'][1]['methods']['ensure']['outputs']['path'] = 'integer'
            account_file.write_text(json.dumps(modified))
            with self.assertRaisesRegex(ValueError, 'invalid method requirement'):
                plan(root)
            account_file.write_text(json.dumps(original))
            modified = copy.deepcopy(original)
            modified['inputs']['shell_path']['from']['output'] = 'secret'
            account_file.write_text(json.dumps(modified))
            with self.assertRaisesRegex(ValueError, 'unavailable or incompatible output'):
                plan(root)
            account_file.write_text(json.dumps(original))
            bindings['login-shell@1#interactive'] = 'missing-provider'
            (root / 'bindings.json').write_text(json.dumps(bindings))
            with self.assertRaisesRegex(ValueError, 'missing binding for implementation'):
                plan(root)

    def test_dependency_cycle_fails(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = Path(temporary)
            (root / 'modules').mkdir()
            for file in (ROOT / 'modules').glob('*/module.json'):
                folder = root / 'modules' / file.parent.name
                folder.mkdir()
                (folder / 'module.json').write_text(file.read_text())
                for script in file.parent.glob('*.yml'):
                    (folder / script.name).write_text(script.read_text())
            (root / 'bindings.json').write_text((ROOT / 'bindings.json').read_text())
            os_file = root / 'modules/opensuse-tumbleweed/module.json'
            os_module = json.loads(os_file.read_text())
            os_module['requires'] = [{"interface": "account@1", "instance": "agentic", "methods": {"ensure": {"args": {}, "outputs": {}}}}]
            os_file.write_text(json.dumps(os_module))
            with self.assertRaisesRegex(ValueError, 'dependency cycle'):
                plan(root)


if __name__ == '__main__':
    unittest.main()
