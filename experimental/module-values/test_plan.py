import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, expand, playbook


class ExpansionTests(unittest.TestCase):
    def test_static_shell_path_is_substituted_before_ansible(self):
        expanded = expand()
        self.assertEqual([instance['id'] for instance in expanded], ['host', 'interactive', 'agentic'])
        self.assertEqual(expanded[0]['interface'], 'opensuse-tumbleweed@1')
        account = expanded[-1]
        self.assertEqual(account['dependencies'], ['host', 'interactive'])
        self.assertEqual(account['args']['account_name'], {'value': 'agentic', 'source': 'config'})
        self.assertEqual(account['args']['shell_path'], {'value': '/usr/bin/zsh', 'source': {
            'interface': 'login-shell@1', 'instance': 'interactive', 'value': 'path'}})
        self.assertNotIn('ansible', json.dumps(expanded))
        rendered = playbook(expanded)
        self.assertIn('shell_path: "/usr/bin/zsh"', rendered)
        self.assertIn('provided_path: "/usr/bin/zsh"', rendered)
        self.assertNotIn('deployment_results', rendered)
        self.assertLess(rendered.index('modules/zsh-on-tumbleweed/ensure.yml'), rendered.index('modules/tumbleweed-local-account/ensure.yml'))
        zsh_script = (ROOT / 'modules/zsh-on-tumbleweed/ensure.yml').read_text()
        self.assertNotIn('command -v', zsh_script)
        self.assertIn("path: '{{ provided_path }}'", zsh_script)
        account_script = (ROOT / 'modules/tumbleweed-local-account/ensure.yml').read_text()
        self.assertNotIn('/bin/zsh', account_script)
        self.assertNotIn('name: agentic', account_script)

    def test_two_accounts_share_same_implementation_and_value(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            reviewer = {'id': 'reviewer', 'module': 'tumbleweed-local-account',
                        'bindings': {'opensuse-tumbleweed@1': 'host', 'login-shell@1': 'interactive'},
                        'inputs': {'account_name': 'reviewer'}}
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            expanded = expand(root)
            self.assertEqual([instance['id'] for instance in expanded], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual(expanded[-1]['args']['shell_path']['value'], '/usr/bin/zsh')
            rendered = playbook(expanded)
            self.assertEqual(rendered.count('modules/tumbleweed-local-account/ensure.yml'), 2)
            self.assertEqual(rendered.count('modules/zsh-on-tumbleweed/ensure.yml'), 1)
            self.assertIn('account_name: "reviewer"', rendered)

    def test_invalid_path_unknown_value_binding_and_cycle_fail_at_expansion(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            zsh_file = root / 'modules/zsh-on-tumbleweed/module.json'
            zsh = json.loads(zsh_file.read_text())
            zsh['values']['path'] = 'relative/zsh'
            zsh_file.write_text(json.dumps(zsh))
            with self.assertRaisesRegex(ValueError, 'invalid provided value'):
                expand(root)
            zsh = json.loads((ROOT / 'modules/zsh-on-tumbleweed/module.json').read_text())
            zsh['requires'] = ['os-base@1']
            zsh_file.write_text(json.dumps(zsh))
            with self.assertRaisesRegex(ValueError, 'unknown or duplicate required interface'):
                expand(root)
            zsh_file.write_text((ROOT / 'modules/zsh-on-tumbleweed/module.json').read_text())
            account_file = root / 'modules/tumbleweed-local-account/module.json'
            account = json.loads(account_file.read_text())
            account['uses'][0]['value'] = 'missing'
            account_file.write_text(json.dumps(account))
            with self.assertRaisesRegex(ValueError, 'unknown static value'):
                expand(root)
            account_file.write_text((ROOT / 'modules/tumbleweed-local-account/module.json').read_text())
            instance_file = root / 'instances/agentic.json'
            instance = json.loads(instance_file.read_text())
            instance['bindings']['login-shell@1'] = 'host'
            instance_file.write_text(json.dumps(instance))
            with self.assertRaisesRegex(ValueError, 'binding does not provide'):
                expand(root)
            instance_file.write_text((ROOT / 'instances/agentic.json').read_text())
            os_file = root / 'modules/opensuse-tumbleweed/module.json'
            os_module = json.loads(os_file.read_text())
            os_module['requires'] = ['account@1']
            os_file.write_text(json.dumps(os_module))
            host_file = root / 'instances/host.json'
            host = json.loads(host_file.read_text())
            host['bindings']['account@1'] = 'agentic'
            host_file.write_text(json.dumps(host))
            with self.assertRaisesRegex(ValueError, 'dependency cycle'):
                expand(root)

    @staticmethod
    def copy_experiment(root):
        for directory in ('modules', 'instances', 'interfaces'):
            shutil.copytree(ROOT / directory, root / directory)
        return root


if __name__ == '__main__':
    unittest.main()
