import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, expand, script


class ExpansionTests(unittest.TestCase):
    def test_static_path_and_bound_substrate_transitions(self):
        expanded = expand()
        self.assertEqual([item['id'] for item in expanded], ['host', 'interactive', 'agentic'])
        host, shell, account = expanded
        self.assertEqual(shell['actions'][0]['args'], ['zsh', '/usr/bin/zsh'])
        self.assertEqual(json.loads((ROOT / 'modules/zsh/module.json').read_text())['lookups']['login-shell@1']['path'], '/usr/bin/zsh')
        self.assertNotIn('zsh', (ROOT / 'interfaces/login-shell.v1.json').read_text().lower())
        self.assertNotIn('zsh', (ROOT / 'interfaces/login-shell-host.v1.json').read_text().lower())
        self.assertEqual(account['args']['shell_path'], {'value': '/usr/bin/zsh', 'source': {
            'interface': 'login-shell@1', 'instance': 'interactive', 'lookup': 'path'}})
        self.assertEqual([step['script'] for item in expanded for step in item['actions']],
                         ['ensure-os.sh', 'ensure-shell.sh', 'ensure-account.sh'])
        self.assertEqual(shell['actions'][0]['provider'], 'host')
        self.assertEqual(account['actions'][0]['provider'], 'host')
        self.assertEqual(account['actions'][0]['args'], ['agentic', '/usr/bin/zsh'])
        self.assertNotIn('ansible', json.dumps(expanded) + script(expanded))
        rendered = script(expanded)
        self.assertIn("sh -s -- zsh /usr/bin/zsh <<'AGENTIC_TASK_1'", rendered)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TASK_2'", rendered)
        self.assertIn('AGENTIC_CONSOLE_VERIFIED', rendered)

    def test_two_accounts_share_substrate_and_shell(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            reviewer = {'id': 'reviewer', 'module': 'local-account',
                        'bindings': {'local-account-host@1': 'host', 'login-shell@1': 'interactive'},
                        'inputs': {'account_name': 'reviewer'}}
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            expanded = expand(root)
            self.assertEqual([item['id'] for item in expanded], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual(expanded[-1]['actions'][0]['args'], ['reviewer', '/usr/bin/zsh'])
            rendered = script(expanded, root)
            self.assertEqual(rendered.count('zypper -n install "$package"'), 1)
            self.assertEqual(rendered.count('useradd -m -s'), 2)

    def test_shell_module_owns_path_and_host_owns_provisioning_method(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            alternative = root / 'modules/alternative-host'
            shutil.copytree(root / 'modules/opensuse-tumbleweed', alternative)
            file = alternative / 'module.json'
            module = json.loads(file.read_text())
            module['id'] = 'alternative-host'
            file.write_text(json.dumps(module))
            shell_dir = root / 'modules/zsh-alternative'
            shutil.copytree(root / 'modules/zsh', shell_dir)
            shell_file = shell_dir / 'module.json'
            shell_module = json.loads(shell_file.read_text())
            shell_module['id'] = 'zsh-alternative'
            shell_module['lookups']['login-shell@1']['path'] = '/opt/zsh/bin/zsh'
            shell_file.write_text(json.dumps(shell_module))
            shell_instance = root / 'instances/interactive.json'
            shell = json.loads(shell_instance.read_text())
            shell['module'] = 'zsh-alternative'
            shell_instance.write_text(json.dumps(shell))
            (alternative / 'ensure-shell.sh').write_text('echo alternative-substrate-method\n')
            host_file = root / 'instances/host.json'
            host = json.loads(host_file.read_text())
            host['module'] = 'alternative-host'
            host_file.write_text(json.dumps(host))
            expanded = expand(root)
            self.assertEqual(expanded[1]['actions'][0]['args'], ['zsh', '/opt/zsh/bin/zsh'])
            self.assertEqual(expanded[2]['actions'][0]['args'], ['agentic', '/opt/zsh/bin/zsh'])
            rendered = script(expanded, root)
            self.assertIn('alternative-substrate-method', rendered)
            self.assertNotIn('zypper -n install zsh', rendered)

    def test_invalid_path_binding_call_and_cycle_fail_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            shell_file = root / 'modules/zsh/module.json'
            shell_module = json.loads(shell_file.read_text())
            shell_module['lookups']['login-shell@1']['path'] = 'relative/zsh'
            shell_file.write_text(json.dumps(shell_module))
            with self.assertRaisesRegex(ValueError, 'invalid lookup declaration'):
                expand(root)
            shell_file.write_text((ROOT / 'modules/zsh/module.json').read_text())
            host_file = root / 'modules/opensuse-tumbleweed/module.json'
            instance_file = root / 'instances/interactive.json'
            instance = json.loads(instance_file.read_text())
            instance['bindings']['login-shell-host@1'] = 'agentic'
            instance_file.write_text(json.dumps(instance))
            with self.assertRaisesRegex(ValueError, 'binding does not provide'):
                expand(root)
            instance_file.write_text((ROOT / 'instances/interactive.json').read_text())
            account_file = root / 'modules/local-account/module.json'
            account = json.loads(account_file.read_text())
            account['calls'][0]['args']['shell_path'] = 'missing'
            account_file.write_text(json.dumps(account))
            with self.assertRaisesRegex(ValueError, 'invalid call argument'):
                expand(root)
            account_file.write_text((ROOT / 'modules/local-account/module.json').read_text())
            host = json.loads(host_file.read_text())
            host['requires'] = ['account@1']
            host_file.write_text(json.dumps(host))
            host_instance_file = root / 'instances/host.json'
            host_instance = json.loads(host_instance_file.read_text())
            host_instance['bindings']['account@1'] = 'agentic'
            host_instance_file.write_text(json.dumps(host_instance))
            with self.assertRaisesRegex(ValueError, 'dependency cycle'):
                expand(root)

    @staticmethod
    def copy_experiment(root):
        for directory in ('modules', 'instances', 'interfaces'):
            shutil.copytree(ROOT / directory, root / directory)
        return root


if __name__ == '__main__':
    unittest.main()
