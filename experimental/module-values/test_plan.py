import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, expand, script


class ExpansionTests(unittest.TestCase):
    def test_instance_reads_no_argument_lookup_from_concrete_shell_module(self):
        host, shell, account = expand()
        self.assertEqual([host['id'], shell['id'], account['id']], ['host', 'interactive', 'agentic'])
        self.assertEqual(shell['lookups']['path'], '/usr/bin/zsh')
        self.assertEqual(shell['actions'][0]['module'], 'zsh-on-tumbleweed')
        self.assertEqual(shell['actions'][0]['args'], ['/usr/bin/zsh'])
        self.assertEqual(account['args']['shell_path'], {'value': '/usr/bin/zsh', 'source': {
            'interface': 'login-shell@1', 'instance': 'interactive', 'lookup': 'path'}})
        self.assertEqual(account['actions'][0]['args'], ['agentic', '/usr/bin/zsh'])
        self.assertEqual(account['actions'][0]['module'], 'tumbleweed-local-account')
        account_script = (ROOT / 'modules/tumbleweed-local-account/ensure.sh').read_text()
        self.assertNotIn('agentic', account_script)
        self.assertNotIn('/usr/bin/zsh', account_script)
        self.assertIn('Not Tumbleweed', account_script)
        self.assertIn('Not Tumbleweed', (ROOT / 'modules/zsh-on-tumbleweed/ensure.sh').read_text())
        self.assertNotIn('zsh', (ROOT / 'interfaces/login-shell.v1.json').read_text().lower())
        self.assertNotIn('ansible', json.dumps(expand()) + script(expand()))
        rendered = script(expand())
        self.assertLess(rendered.index('# host:'), rendered.index('# interactive:'))
        self.assertIn("sh -s -- /usr/bin/zsh <<'AGENTIC_TASK_1'", rendered)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TASK_2'", rendered)
        self.assertIn('AGENTIC_CONSOLE_VERIFIED', rendered)

    def test_two_accounts_share_the_same_shell_instance(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            reviewer = {'id': 'reviewer', 'module': 'tumbleweed-local-account',
                        'bindings': {'os@1': 'host', 'login-shell@1': 'interactive'},
                        'inputs': {'account_name': 'reviewer'}}
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            expanded = expand(root)
            self.assertEqual([item['id'] for item in expanded], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual(expanded[-1]['actions'][0]['args'], ['reviewer', '/usr/bin/zsh'])
            rendered = script(expanded, root)
            self.assertEqual(rendered.count('zypper -n install zsh'), 1)
            self.assertEqual(rendered.count('useradd -m -s'), 2)

    def test_other_shell_implementation_changes_lookup_without_changing_interfaces(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            alternative = root / 'modules/other-shell'
            shutil.copytree(root / 'modules/zsh-on-tumbleweed', alternative)
            file = alternative / 'module.json'
            module = json.loads(file.read_text())
            module['id'] = 'other-shell'
            module['lookups']['path'] = '/opt/other/bin/shell'
            file.write_text(json.dumps(module))
            (alternative / 'ensure.sh').write_text('echo other-shell-implementation\n')
            shell_file = root / 'instances/interactive.json'
            shell = json.loads(shell_file.read_text())
            shell['module'] = 'other-shell'
            shell_file.write_text(json.dumps(shell))
            expanded = expand(root)
            self.assertEqual(expanded[2]['args']['shell_path']['value'], '/opt/other/bin/shell')
            self.assertEqual(expanded[1]['actions'][0]['module'], 'other-shell')
            self.assertIn('other-shell-implementation', script(expanded, root))

    def test_invalid_lookup_binding_and_cycle_fail_before_execution(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_experiment(Path(temporary))
            shell_file = root / 'modules/zsh-on-tumbleweed/module.json'
            shell_module = json.loads(shell_file.read_text())
            shell_module['lookups']['path'] = 'relative/zsh'
            shell_file.write_text(json.dumps(shell_module))
            with self.assertRaisesRegex(ValueError, 'invalid lookup declaration'):
                expand(root)
            shell_file.write_text((ROOT / 'modules/zsh-on-tumbleweed/module.json').read_text())
            instance_file = root / 'instances/agentic.json'
            instance = json.loads(instance_file.read_text())
            instance['bindings']['login-shell@1'] = 'host'
            instance_file.write_text(json.dumps(instance))
            with self.assertRaisesRegex(ValueError, 'binding does not provide'):
                expand(root)
            instance_file.write_text((ROOT / 'instances/agentic.json').read_text())
            account_file = root / 'modules/tumbleweed-local-account/module.json'
            account = json.loads(account_file.read_text())
            account['uses'][0]['lookup'] = 'missing'
            account_file.write_text(json.dumps(account))
            with self.assertRaisesRegex(ValueError, 'invalid static use'):
                expand(root)
            account_file.write_text((ROOT / 'modules/tumbleweed-local-account/module.json').read_text())
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
