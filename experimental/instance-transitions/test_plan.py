import json
import shutil
import tempfile
import unittest
from pathlib import Path
from plan import ROOT, artifact_id, expand, load, reference_id, script

AUTHORITY = 'did:web:agentic.invalid'  # claimed fixture; NOT resolved or authenticated


def ref(kind, name, version=1, authority=AUTHORITY):
    return {'kind': kind, 'authority': authority, 'name': name, 'version': version}


def link(kind, name, version=1, authority=AUTHORITY):
    return f'{authority}#{kind}/{name}@{version}'


def local(kind, name, version=1):
    return f'{kind}/{name}@{version}'


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
        self.assertEqual(steps[2]['calls'][0]['args'], ['agentic', '/usr/bin/zsh'])
        self.assertEqual(steps[2]['calls'][0]['instance'], 'agentic')
        rendered = script(steps)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TRANSITION_2'", rendered)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_METHOD_2_0'", rendered)
        self.assertNotIn('ansible', rendered)
        self.assertNotIn('agentic', (ROOT / 'transitions/introduce-account/run.sh').read_text())
        for directory, filename in (('modules', 'module.json'), ('transitions', 'transition.json'),
                                    ('interfaces', '*.json')):
            for file in (ROOT / directory).rglob(filename):
                declaration = json.loads(file.read_text())
                self.assertNotIn('id', declaration)
                self.assertEqual(set(ref(declaration['kind'], declaration['name'],
                                             declaration['version'], declaration['authority'])),
                                 {'kind', 'authority', 'name', 'version'})
                if directory == 'modules':
                    self.assertFalse({'script', 'transitions', 'entrypoint'} & set(declaration))

    def test_full_interface_catalog_and_dependency_graph(self):
        interfaces, _, _ = load(ROOT)
        self.assertEqual({key[2] for key in interfaces}, {
            'os', 'package-manager', 'networking', 'firewall', 'ssh-access',
            'intrusion-prevention', 'mandatory-access-control', 'kernel-hardening',
            'account', 'recovery-access', 'login-shell', 'workspace', 'git-client',
            'sandbox', 'agent-harness', 'skills', 'backup', 'scheduler',
            'diagnostics', 'status-screen', 'github-app-credentials', 'github-mcp',
            'git-credentials', 'github-protection-audit'})
        by_name = {key[2]: doc for key, doc in interfaces.items()}
        self.assertEqual(by_name['firewall']['requires'], [local('interface', 'networking')])
        self.assertEqual(by_name['ssh-access']['requires'],
                         [local('interface', 'networking'), local('interface', 'firewall')])
        self.assertEqual(by_name['git-credentials']['requires'],
                         [local('interface', 'git-client'), local('interface', 'github-app-credentials')])
        self.assertNotIn(local('interface', 'git-client'), by_name['github-mcp']['requires'])
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            file = root / 'interfaces/networking.v1.json'
            networking = json.loads(file.read_text())
            networking['requires'] = [local('interface', 'firewall')]
            file.write_text(json.dumps(networking))
            with self.assertRaisesRegex(ValueError, 'interface dependency cycle'):
                load(root)
            networking['requires'] = [local('interface', 'missing')]
            file.write_text(json.dumps(networking))
            with self.assertRaisesRegex(ValueError, 'invalid interface dependencies'):
                load(root)
            file.write_text((ROOT / 'interfaces/networking.v1.json').read_text())
            account = root / 'modules/linux-local-account/module.json'
            module = json.loads(account.read_text())
            module['requires'] = [local('interface', 'login-shell')]
            account.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, 'invalid required interfaces'):
                load(root)
            account.write_text((ROOT / 'modules/linux-local-account/module.json').read_text())
            spec = root / 'interfaces/firewall.v1.json'
            firewall = json.loads(spec.read_text())
            firewall['methods']['ensure_ingress']['params'].append('port')
            spec.write_text(json.dumps(firewall))
            with self.assertRaisesRegex(ValueError, 'invalid interface method'):
                load(root)

    def test_transition_invokes_bound_provider_method_before_its_script(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            file = root / 'transitions/introduce-account/transition.json'
            transition = json.loads(file.read_text())
            transition['calls'].insert(0, {'phase': 'before', 'side': 'to',
                'via': local('interface', 'login-shell'), 'method': 'inspect', 'params': {}})
            file.write_text(json.dumps(transition))
            steps = expand(root)
            self.assertEqual(steps[2]['calls'][0]['instance'], 'interactive')
            self.assertEqual(steps[2]['calls'][0]['args'], ['/usr/bin/zsh'])
            rendered = script(steps, root)
            self.assertLess(rendered.index('# interactive.inspect'), rendered.index('# agentic:'))
            transition['calls'][0]['via'] = local('interface', 'firewall')
            file.write_text(json.dumps(transition))
            with self.assertRaisesRegex(ValueError, 'method provider is not bound'):
                expand(root)
            transition['calls'][0]['via'] = local('interface', 'login-shell')
            transition['calls'][0]['params'] = {'unexpected': {'literal': 'x'}}
            file.write_text(json.dumps(transition))
            with self.assertRaisesRegex(ValueError, 'unknown method or parameters'):
                expand(root)
            module_file = root / 'modules/zsh-on-tumbleweed/module.json'
            module = json.loads(module_file.read_text())
            module['methods']['inspect']['script'] = 'methods/../../run.sh'
            module_file.write_text(json.dumps(module))
            with self.assertRaisesRegex(ValueError, 'invalid method implementation'):
                load(root)

    def test_two_accounts_share_module_and_provider_under_distinct_instance_ids(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            reviewer = json.loads((root / 'instances/agentic.json').read_text())
            reviewer['id'] = 'reviewer'
            reviewer['inputs']['account_name'] = 'reviewer'
            (root / 'instances/reviewer.json').write_text(json.dumps(reviewer))
            requests = self.requests(root)
            requests['transitions'].append({'instance': 'reviewer', 'transition': link('transition', 'introduce-account')})
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([s['instance'] for s in steps], ['host', 'interactive', 'agentic', 'reviewer'])
            self.assertEqual([arg['value'] for arg in steps[-1]['args']], ['reviewer', '/usr/bin/zsh'])

    def test_explicit_upgrade_can_read_both_module_versions(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            old = root / 'modules/old-zsh'
            old.mkdir()
            shutil.copytree(root / 'modules/zsh-on-tumbleweed/methods', old / 'methods')
            (old / 'module.json').write_text(json.dumps({
                **ref('module', 'legacy-zsh', authority='did:web:other.invalid'),
                'implements': link('interface', 'login-shell'), 'requires': [link('interface', 'os')],
                'values': {'path': '/old/bin/zsh'}, 'config': {}, 'uses': [],
                'methods': {'inspect': {'script': 'methods/inspect.sh', 'args': ['path']}}}))
            upgrade = root / 'transitions/upgrade-zsh'
            upgrade.mkdir()
            (upgrade / 'run.sh').write_text('#!/bin/sh\nexit 0\n')
            (upgrade / 'transition.json').write_text(json.dumps({
                **ref('transition', 'upgrade-zsh'), 'interface': local('interface', 'login-shell'),
                'from': link('module', 'legacy-zsh', authority='did:web:other.invalid'),
                'to': local('module', 'zsh-on-tumbleweed'),
                'script': 'run.sh', 'args': [{'side': 'from', 'name': 'path'}, {'side': 'to', 'name': 'path'}]}))
            requests = self.requests(root)
            requests['transitions'][1]['transition'] = link('transition', 'upgrade-zsh')
            requests['transitions'][1]['from_bindings'] = json.loads(
                (root / 'instances/interactive.json').read_text())['bindings']
            os_transition_file = root / 'transitions/introduce-os/transition.json'
            os_transition = json.loads(os_transition_file.read_text())
            os_transition['from'] = local('module', 'opensuse-tumbleweed')
            os_transition_file.write_text(json.dumps(os_transition))
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
                    'transition': link('transition', 'remove-' + suffix),
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
                    **ref('transition', 'remove-' + suffix), 'interface': local('interface', iface),
                    'from': local('module', module), 'to': None, 'script': 'run.sh', 'args': args}))
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual([s['instance'] for s in steps], ['agentic', 'interactive', 'host'])
            self.assertEqual(steps[0]['args'][0]['value'], '/usr/bin/zsh')

    def test_coordinates_are_kind_scoped_and_exact_duplicates_fail(self):
        self.assertEqual(reference_id(local('interface', 'os'), 'interface', AUTHORITY),
                         artifact_id(ref('interface', 'os'), 'interface'))
        self.assertEqual(reference_id(link('module', 'shared', authority='did:web:other.invalid'), 'module'),
                         artifact_id(ref('module', 'shared', authority='did:web:other.invalid'), 'module'))
        with self.assertRaisesRegex(ValueError, 'unscoped'):
            reference_id(local('interface', 'os'), 'interface')
        with self.assertRaisesRegex(ValueError, 'invalid module identity'):
            reference_id(local('interface', 'os'), 'module', AUTHORITY)
        with self.assertRaisesRegex(ValueError, 'invalid or unscoped'):
            reference_id('did:web:agentic.invalid#interface/os@01', 'interface')
        self.assertNotEqual(artifact_id(ref('module', 'shared'), 'module'),
                            artifact_id(ref('interface', 'shared'), 'interface'))
        self.assertNotEqual(artifact_id(ref('module', 'shared'), 'module'),
                            artifact_id(ref('module', 'shared', authority='did:web:other.invalid'), 'module'))
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
            shutil.copytree(root / 'modules/opensuse-tumbleweed/methods', duplicate / 'methods')
            with self.assertRaisesRegex(ValueError, 'duplicate artifact identity'):
                expand(root)
            other = json.loads((duplicate / 'module.json').read_text())
            other['authority'] = 'did:web:other.invalid'
            other['implements'] = link('interface', 'os')
            (duplicate / 'module.json').write_text(json.dumps(other))
            self.assertEqual(expand(root)[0]['to'], ref('module', 'opensuse-tumbleweed'))
            other['authority'] = AUTHORITY
            other['implements'] = local('interface', 'os')
            other['version'] = 2
            (duplicate / 'module.json').write_text(json.dumps(other))
            self.assertEqual(expand(root)[0]['to'], ref('module', 'opensuse-tumbleweed'))

    def test_two_distinct_transitions_can_have_same_endpoints_when_requested_explicitly(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            folder = root / 'transitions/alternative-os'
            folder.mkdir()
            shutil.copy(root / 'transitions/introduce-os/run.sh', folder / 'run.sh')
            spec = json.loads((root / 'transitions/introduce-os/transition.json').read_text())
            spec['name'] = 'alternative-os'
            (folder / 'transition.json').write_text(json.dumps(spec))
            requests = self.requests(root)
            requests['transitions'][0]['transition'] = link('transition', 'alternative-os')
            steps = expand(root, self.save_requests(root, requests))
            self.assertEqual(steps[0]['transition'], ref('transition', 'alternative-os'))

    def test_missing_mismatched_or_invalid_requests_fail_closed(self):
        with tempfile.TemporaryDirectory() as temporary:
            root = self.copy_model(Path(temporary))
            requests = self.requests(root)
            requests['transitions'].pop()
            with self.assertRaisesRegex(ValueError, 'explicitly name every'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'].append({'instance': 'agentic', 'transition': link('transition', 'introduce-zsh')})
            with self.assertRaisesRegex(ValueError, 'requested transition to does not match'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'][-1]['transition'] = link('transition', 'introduce-account')
            requests['transitions'][-1]['from_inputs'] = {'account_name': 'agentic'}
            with self.assertRaisesRegex(ValueError, 'absent from cannot'):
                expand(root, self.save_requests(root, requests))
            requests['transitions'][-1].pop('from_inputs')
            host_file = root / 'instances/host.json'
            host = json.loads(host_file.read_text())
            host['module'] = local('module', 'opensuse-tumbleweed')
            host_file.write_text(json.dumps(host))
            with self.assertRaisesRegex(ValueError, 'unscoped module reference'):
                expand(root)
            host_file.write_text((ROOT / 'instances/host.json').read_text())
            folder = root / 'transitions/invalid'
            folder.mkdir()
            (folder / 'run.sh').write_text('exit 0\n')
            (folder / 'transition.json').write_text(json.dumps({
                **ref('transition', 'invalid'), 'interface': local('interface', 'account'),
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
