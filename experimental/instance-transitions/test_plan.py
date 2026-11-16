import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, artifact_id, expand, script

PUBLISHER = 'did:web:agentic.invalid'  # fixture only; NOT resolved or authenticated


def ref(kind, name, version=1, publisher=PUBLISHER):
    return {'kind': kind, 'publisher': publisher, 'name': name, 'version': version}


class TransitionTests(unittest.TestCase):
    def test_introduction_resolves_bound_value_and_identified_endpoints(self):
        steps = expand()
        self.assertEqual([step['transition']['name'] for step in steps],
                         ['introduce-os', 'introduce-zsh', 'introduce-account'])
        self.assertEqual([step['from'] for step in steps], [None, None, None])
        self.assertEqual(steps[1]['to'], ref('module', 'zsh-on-tumbleweed'))
        self.assertEqual(steps[1]['args'][0]['value'], '/usr/bin/zsh')
        self.assertEqual(steps[2]['args'][1], {'value': '/usr/bin/zsh', 'source': {'side': 'to',
            'detail': {'interface': ref('interface', 'login-shell'), 'instance': 'interactive', 'value': 'path'}}})
        self.assertEqual(steps[2]['script'], 'transitions/introduce-account/run.sh')
        rendered = script(steps)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TRANSITION_2'", rendered)
        self.assertNotIn('ansible', rendered)
        self.assertNotIn('agentic', (ROOT / 'transitions/introduce-account/run.sh').read_text())
        for file in (ROOT / 'modules').rglob('module.json'):
            self.assertFalse({'script', 'transitions', 'entrypoint'} & set(json.loads(file.read_text())))

    def test_two_accounts_share_module_and_provider_under_distinct_instance_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            reviewer = json.loads((root / 'instances/agentic.json').read_text())
            reviewer['id'] = 'reviewer'
            reviewer['inputs']['account_name'] = 'reviewer'
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            requests = self.requests(root)
            requests['transitions'].append({'instance': 'reviewer', 'transition': ref('transition', 'introduce-account')})
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([s['instance'] for s in steps], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual([arg['value'] for arg in steps[-1]['args']], ['reviewer', '/usr/bin/zsh'])

    def test_explicit_upgrade_can_read_both_module_versions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            old = root / 'modules/old-zsh'
            old.mkdir()
            (old / 'module.json').write_text(json.dumps({
                'id': ref('module', 'legacy-zsh'),
                'implements': ref('interface', 'login-shell'), 'requires': [],
                'values': {'path': '/old/bin/zsh'}, 'config': {}, 'uses': []}))
            upgrade = root / 'transitions/upgrade-zsh'
            upgrade.mkdir()
            (upgrade / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
            (upgrade / 'transition.json').write_text(json.dumps({
                'id': ref('transition', 'upgrade-zsh'), 'interface': ref('interface', 'login-shell'),
                'from': ref('module', 'legacy-zsh'), 'to': ref('module', 'zsh-on-tumbleweed'),
                'script': 'run.sh', 'args': [{'side': 'from', 'name': 'path'}, {'side': 'to', 'name': 'path'}]}))
            requests = self.requests(root)
            requests['transitions'][1]['transition'] = ref('transition', 'upgrade-zsh')
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([arg['value'] for arg in steps[1]['args']], ['/old/bin/zsh', '/usr/bin/zsh'])
            self.assertEqual(steps[2]['args'][1]['value'], '/usr/bin/zsh')

    def test_removal_orders_dependents_before_providers_and_reads_from_declarations(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            requests = {'transitions': []}
            for file in (root / 'instances').glob('*.json'):
                entry = json.loads(file.read_text())
                suffix = {'host': 'os', 'interactive': 'zsh', 'agentic': 'account'}[entry['id']]
                requests['transitions'].append({'instance': entry['id'],
                    'transition': ref('transition', 'remove-' + suffix),
                    'from_inputs': entry['inputs'], 'from_bindings': entry['bindings']})
                file.write_text(json.dumps({'id': entry['id'], 'module': None}))
            for iface, module, suffix, args in (
                ('account', 'linux-local-account', 'account', [{'side': 'from', 'name': 'shell_path'}]),
                ('login-shell', 'zsh-on-tumbleweed', 'zsh', []),
                ('os', 'opensuse-tumbleweed', 'os', []),
            ):
                folder = root / 'transitions' / ('remove-' + suffix)
                folder.mkdir()
                (folder / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
                (folder / 'transition.json').write_text(json.dumps({
                    'id': ref('transition', 'remove-' + suffix), 'interface': ref('interface', iface),
                    'from': ref('module', module), 'to': None, 'script': 'run.sh', 'args': args}))
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([s['instance'] for s in steps], ['agentic', 'interactive', 'host'])
            self.assertEqual(steps[0]['args'][0]['value'], '/usr/bin/zsh')

    def test_coordinates_are_kind_scoped_and_exact_duplicates_fail(self):
        self.assertNotEqual(artifact_id(ref('module', 'shared'), 'module'),
                            artifact_id(ref('interface', 'shared'), 'interface'))
        self.assertNotEqual(artifact_id(ref('module', 'shared'), 'module'),
                            artifact_id(ref('module', 'shared', publisher='did:web:other.invalid'), 'module'))
        self.assertNotEqual(artifact_id(ref('module', 'shared'), 'module'),
                            artifact_id(ref('module', 'shared', version=2), 'module'))
        with self.assertRaisesRegex(ValueError, 'invalid module identity'):
            artifact_id(ref('interface', 'shared'), 'module')
        with self.assertRaisesRegex(ValueError, 'invalid module identity'):
            artifact_id(ref('module', 'shared', version=0), 'module')
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            duplicate = root / 'modules/duplicate'
            duplicate.mkdir()
            shutil.copy(root / 'modules/opensuse-tumbleweed/module.json', duplicate / 'module.json')
            with self.assertRaisesRegex(ValueError, 'duplicate artifact identity'):
                expand(root)
            other = json.loads((duplicate / 'module.json').read_text())
            other['id']['publisher'] = 'did:web:other.invalid'
            (duplicate / 'module.json').write_text(json.dumps(other))
            self.assertEqual(expand(root)[0]['to'], ref('module', 'opensuse-tumbleweed'))
            other['id']['publisher'] = PUBLISHER
            other['id']['version'] = 2
            (duplicate / 'module.json').write_text(json.dumps(other))
            self.assertEqual(expand(root)[0]['to'], ref('module', 'opensuse-tumbleweed'))

    def test_two_distinct_transitions_can_have_same_endpoints_when_requested_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            folder = root / 'transitions/alternative-os'
            folder.mkdir()
            shutil.copy(root / 'transitions/introduce-os/run.sh', folder / 'run.sh')
            spec = json.loads((root / 'transitions/introduce-os/transition.json').read_text())
            spec['id'] = ref('transition', 'alternative-os')
            (folder / 'transition.json').write_text(json.dumps(spec))
            requests = self.requests(root)
            requests['transitions'][0]['transition'] = ref('transition', 'alternative-os')
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual(steps[0]['transition'], ref('transition', 'alternative-os'))

    def test_missing_mismatched_or_invalid_requests_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            requests = self.requests(root)
            requests['transitions'].pop()
            with self.assertRaisesRegex(ValueError, 'explicitly name every'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'].append({'instance': 'agentic', 'transition': ref('transition', 'introduce-zsh')})
            with self.assertRaisesRegex(ValueError, 'requested transition to does not match'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'][-1]['transition'] = ref('transition', 'introduce-account')
            requests['transitions'][-1]['from_inputs'] = {'account_name': 'agentic'}
            with self.assertRaisesRegex(ValueError, 'absent from cannot'):
                expand(root, self.save_requests(root, requests))
            folder = root / 'transitions/invalid'
            folder.mkdir()
            (folder / 'run.sh').write_text('exit 0\n')
            (folder / 'transition.json').write_text(json.dumps({
                'id': ref('transition', 'invalid'), 'interface': ref('interface', 'account'),
                'from': None, 'to': None, 'script': 'run.sh', 'args': []}))
            with self.assertRaisesRegex(ValueError, 'needs a from or to module'):
                expand(root)

    @staticmethod
    def requests(root):
        return json.loads((root / 'requests/introduction.json').read_text())

    @staticmethod
    def save_requests(root, request):
        file = root / 'requests/test.generated.json'
        file.write_text(json.dumps(request))
        return file

    @staticmethod
    def copy_model(root):
        for directory in ('interfaces', 'modules', 'instances', 'transitions', 'requests'):
            shutil.copytree(ROOT / directory, root / directory)
        return root


if __name__ == '__main__':
    unittest.main()
