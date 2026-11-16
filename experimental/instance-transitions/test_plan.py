import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, expand, script


class TransitionTests(unittest.TestCase):
    def test_explicit_introduction_uses_static_shell_value_and_bound_instances(self):
        steps = expand()
        self.assertEqual([step['transition'] for step in steps],
                         ['introduce-os', 'introduce-zsh', 'introduce-account'])
        self.assertEqual([step['from'] for step in steps], [None, None, None])
        self.assertEqual(steps[1]['args'][0]['value'], '/usr/bin/zsh')
        self.assertEqual(steps[2]['args'][1], {'value': '/usr/bin/zsh', 'source': {'side': 'to',
            'detail': {'interface': 'login-shell@1', 'instance': 'interactive', 'value': 'path'}}})
        for step in steps:
            self.assertTrue(step['script'].startswith('transitions/'))
        rendered = script(steps)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TRANSITION_2'", rendered)
        self.assertNotIn('ansible', rendered)
        self.assertNotIn('agentic', (ROOT / 'transitions/introduce-account/run.sh').read_text())
        self.assertNotIn('/usr/bin/zsh', (ROOT / 'transitions/introduce-account/run.sh').read_text())
        for file in (ROOT / 'modules').glob('*/module.json'):
            self.assertFalse({'script', 'transitions', 'entrypoint'} & set(json.loads(file.read_text())))

    def test_two_accounts_share_module_and_provider_but_request_separate_transitions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            (root / 'instances/reviewer.json').write_text(json.dumps({
                'id': 'reviewer', 'module': 'linux-local-account',
                'bindings': {'os@1': 'host', 'login-shell@1': 'interactive'},
                'inputs': {'account_name': 'reviewer'}}))
            requests = self.read_requests(root)
            requests['transitions'].append({'instance': 'reviewer', 'transition': 'introduce-account'})
            requested = self.save_requests(root, requests)
            steps = expand(root, requested)
            self.assertEqual([step['instance'] for step in steps], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual(steps[-1]['transition'], 'introduce-account')
            self.assertEqual([arg['value'] for arg in steps[-1]['args']], ['reviewer', '/usr/bin/zsh'])

    def test_explicit_upgrade_uses_from_and_to_module_declarations(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            old = root / 'modules/old-zsh'
            old.mkdir()
            (old / 'module.json').write_text(json.dumps({
                'id': 'old-zsh', 'implements': 'login-shell@1', 'requires': [],
                'values': {'path': '/old/bin/zsh'}, 'config': {}, 'uses': []}))
            transition = root / 'transitions/upgrade-zsh'
            transition.mkdir()
            (transition / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
            (transition / 'transition.json').write_text(json.dumps({
                'id': 'upgrade-zsh', 'interface': 'login-shell@1',
                'from': 'old-zsh', 'to': 'zsh-on-tumbleweed', 'script': 'run.sh',
                'args': [{'side': 'from', 'name': 'path'}, {'side': 'to', 'name': 'path'}]}))
            requests = self.read_requests(root)
            requests['transitions'][1] = {'instance': 'interactive', 'transition': 'upgrade-zsh'}
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual(steps[1]['transition'], 'upgrade-zsh')
            self.assertEqual([arg['value'] for arg in steps[1]['args']], ['/old/bin/zsh', '/usr/bin/zsh'])
            self.assertEqual(steps[2]['args'][1]['value'], '/usr/bin/zsh')

    def test_removal_orders_dependents_before_providers_and_reads_from_declarations(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            requests = {'transitions': []}
            for file in (root / 'instances').glob('*.json'):
                entry = json.loads(file.read_text())
                suffix = {'host': 'os', 'interactive': 'zsh', 'agentic': 'account'}[entry['id']]
                requests['transitions'].append({'instance': entry['id'], 'transition': 'remove-' + suffix,
                    'from_inputs': entry['inputs'], 'from_bindings': entry['bindings']})
                file.write_text(json.dumps({'id': entry['id'], 'module': None}))
            for interface, module, suffix, args in (
                ('account@1', 'linux-local-account', 'account', [{'side': 'from', 'name': 'shell_path'}]),
                ('login-shell@1', 'zsh-on-tumbleweed', 'zsh', []),
                ('os@1', 'opensuse-tumbleweed', 'os', []),
            ):
                folder = root / 'transitions' / ('remove-' + suffix)
                folder.mkdir()
                (folder / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
                (folder / 'transition.json').write_text(json.dumps({
                    'id': 'remove-' + suffix, 'interface': interface, 'from': module,
                    'to': None, 'script': 'run.sh', 'args': args}))
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([step['instance'] for step in steps], ['agentic', 'interactive', 'host'])
            self.assertEqual(steps[0]['args'][0]['value'], '/usr/bin/zsh')

    def test_missing_or_mismatched_request_fails_without_inferring_a_transition(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            requests = self.read_requests(root)
            requests['transitions'].pop()
            with self.assertRaisesRegex(ValueError, 'explicitly name every'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'].append({'instance': 'agentic', 'transition': 'introduce-zsh'})
            with self.assertRaisesRegex(ValueError, 'requested transition to does not match'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'][-1]['transition'] = 'introduce-account'
            requests['transitions'][-1]['from_inputs'] = {'account_name': 'agentic'}
            with self.assertRaisesRegex(ValueError, 'absent from cannot'):
                expand(root, self.save_requests(root, requests))
            invalid = root / 'transitions/invalid'
            invalid.mkdir()
            (invalid / 'run.sh').write_text('exit 0\n')
            (invalid / 'transition.json').write_text(json.dumps({
                'id': 'invalid', 'interface': 'account@1', 'from': None, 'to': None,
                'script': 'run.sh', 'args': []}))
            with self.assertRaisesRegex(ValueError, 'needs a from or to module'):
                expand(root)

    def test_ambiguous_transition_and_mismatched_interface_fail(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            duplicate = root / 'transitions/duplicate-os'
            duplicate.mkdir()
            (duplicate / 'run.sh').write_text('exit 0\n')
            spec = json.loads((root / 'transitions/introduce-os/transition.json').read_text())
            spec['id'] = 'duplicate-os'
            (duplicate / 'transition.json').write_text(json.dumps(spec))
            with self.assertRaisesRegex(ValueError, 'ambiguous transition'):
                expand(root)
            spec['from'] = 'zsh-on-tumbleweed'
            (duplicate / 'transition.json').write_text(json.dumps(spec))
            with self.assertRaisesRegex(ValueError, 'transition endpoint does not implement'):
                expand(root)

    @staticmethod
    def read_requests(root):
        return json.loads((root / 'requests/introduction.json').read_text())

    @staticmethod
    def save_requests(root, requests):
        file = root / 'requests/test.generated.json'
        file.write_text(json.dumps(requests))
        return file

    @staticmethod
    def copy_model(root):
        for name in ('interfaces', 'modules', 'instances', 'transitions', 'requests'):
            shutil.copytree(ROOT / name, root / name)
        return root


if __name__ == '__main__':
    unittest.main()
