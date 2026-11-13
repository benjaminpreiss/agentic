import copy
import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, plan, playbook


class ReusableModuleTests(unittest.TestCase):
    def test_agentic_instance_consumes_verified_shell_result(self):
        ordered = plan()
        self.assertEqual([item['id'] for item in ordered], ['host', 'interactive', 'agentic'])
        rendered = playbook(ordered)
        self.assertIn("deployment_results['login-shell@1#interactive']['path']", rendered)
        self.assertIn('account_name: "agentic"', rendered)
        self.assertIn('shell_path: "{{ deployment_results[', rendered)
        self.assertLess(rendered.index('modules/zsh/ensure.yml'), rendered.index('modules/linux-local-account/ensure.yml'))
        account = (ROOT / 'modules/linux-local-account/ensure.yml').read_text()
        self.assertNotIn('/bin/zsh', account)
        self.assertNotIn('name: agentic', account)
        self.assertIn("name: '{{ account_name }}'", account)

    def test_two_accounts_reuse_one_module_and_one_shell_instance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            reviewer = {"id": "reviewer", "module": "linux-local-account",
                        "bindings": {"os-base@1": "host", "login-shell@1": "interactive"},
                        "inputs": {"account_name": "reviewer"}}
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            ordered = plan(root)
            self.assertEqual([item['id'] for item in ordered], ['host', 'interactive', 'agentic', 'reviewer'])
            rendered = playbook(ordered)
            self.assertEqual(rendered.count('modules/linux-local-account/ensure.yml'), 2)
            self.assertEqual(rendered.count('modules/zsh/ensure.yml'), 1)
            self.assertIn('account_name: "reviewer"', rendered)
            self.assertIn('account@1#reviewer', rendered)

    def test_mismatch_unbound_input_and_cycle_fail_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            account_file = root / 'modules/linux-local-account/module.json'
            original = json.loads(account_file.read_text())
            modified = copy.deepcopy(original)
            modified['requires'][1]['methods']['ensure']['outputs']['path'] = 'integer'
            account_file.write_text(json.dumps(modified))
            with self.assertRaisesRegex(ValueError, 'invalid required method'):
                plan(root)
            account_file.write_text(json.dumps(original))
            modified = copy.deepcopy(original)
            modified['inputs']['shell_path']['from']['output'] = 'secret'
            account_file.write_text(json.dumps(modified))
            with self.assertRaisesRegex(ValueError, 'unavailable or incompatible output'):
                plan(root)
            account_file.write_text(json.dumps(original))
            instance_file = root / 'instances/agentic.json'
            instance = json.loads(instance_file.read_text())
            instance['bindings']['login-shell@1'] = 'host'
            instance_file.write_text(json.dumps(instance))
            with self.assertRaisesRegex(ValueError, 'binding does not provide'):
                plan(root)
            instance_file.write_text((ROOT / 'instances/agentic.json').read_text())
            os_file = root / 'modules/opensuse-tumbleweed/module.json'
            os_module = json.loads(os_file.read_text())
            os_module['requires'] = [{"interface": "account@1", "methods": {"ensure": {"args": {}, "outputs": {}}}}]
            os_file.write_text(json.dumps(os_module))
            host_file = root / 'instances/host.json'
            host = json.loads(host_file.read_text())
            host['bindings']['account@1'] = 'agentic'
            host_file.write_text(json.dumps(host))
            with self.assertRaisesRegex(ValueError, 'dependency cycle'):
                plan(root)

    @staticmethod
    def copy_experiment(root):
        shutil.copytree(ROOT / 'modules', root / 'modules')
        shutil.copytree(ROOT / 'instances', root / 'instances')
        return root


if __name__ == '__main__':
    unittest.main()
