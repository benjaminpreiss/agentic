import json
import shutil
import tempfile
import unittest
from pathlib import Path

from plan import ROOT, expand


class ExecutionGraphTests(unittest.TestCase):
    def copy(self, destination):
        for folder in ('interfaces', 'modules', 'instances', 'transitions'):
            shutil.copytree(ROOT / folder, destination / folder)
        shutil.copy(ROOT / 'requests.json', destination / 'requests.json')
        return destination

    def change(self, root, path, modify):
        file = root / path
        doc = json.loads(file.read_text())
        modify(doc)
        file.write_text(json.dumps(doc))

    def test_runtime_and_executor_are_selected_by_instance_bindings(self):
        steps = expand()
        self.assertEqual([step['instance'] for step in steps],
                         ['bash-admin', 'bash-agent', 'packages', 'python-admin', 'network', 'workspace'])
        network = steps[4]['calls']
        self.assertEqual([(c['runtime'], c['executor']) for c in network],
                         [('bash-admin', 'admin-executor'), ('python-admin', 'admin-executor')])
        self.assertEqual(network[1]['args'], ['192.0.2.10/24'])
        self.assertEqual(steps[5]['calls'][0]['executor'], 'agent-executor')
        self.assertEqual(steps[3]['calls'][0]['receiver'], 'packages')
        self.assertNotIn('script', steps[4])

    def test_missing_or_wrong_runtime_and_cross_target_are_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            network = 'instances/network.json'
            self.change(root, network, lambda doc: doc['bindings'].pop('did:web:agentic.invalid#interface/python-runtime@1'))
            with self.assertRaisesRegex(ValueError, 'missing or duplicate bindings'):
                expand(root)
            shutil.copy(ROOT / network, root / network)
            self.change(root, network, lambda doc: doc.update(target='other-vm'))
            with self.assertRaisesRegex(ValueError, 'cross-target provider'):
                expand(root)

    def test_grants_are_checked_but_not_authenticated_by_planner(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            self.change(root, 'instances/admin-executor.json', lambda doc: doc.update(grants=['network-read']))
            with self.assertRaisesRegex(ValueError, 'unauthorized or cross-target'):
                expand(root)

    def test_executor_choice_comes_from_runtime_instance_not_module_or_method(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            self.change(root, 'instances/agent-executor.json',
                        lambda doc: doc.update(grants=['workspace-read', 'network-read']))
            self.change(root, 'instances/network.json', lambda doc: doc['bindings'].update({
                'did:web:agentic.invalid#interface/bash-runtime@1': 'bash-agent'}))
            calls = next(step for step in expand(root) if step['instance'] == 'network')['calls']
            self.assertEqual(calls[0]['executor'], 'agent-executor')
            self.assertEqual(calls[1]['executor'], 'admin-executor')
            self.change(root, 'modules/bash-on-executor/module.json',
                        lambda doc: doc.update(accepts=['text/x-python']))
            with self.assertRaisesRegex(ValueError, 'runtime rejects artifact format'):
                expand(root)

    def test_bootstrap_executor_must_be_external_unbound_and_grants_are_well_formed(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            self.change(root, 'instances/admin-executor.json',
                        lambda doc: doc.update(grants=['network-read', 'network-read']))
            with self.assertRaisesRegex(ValueError, 'invalid executor grant claims'):
                expand(root)
            shutil.copy(ROOT / 'instances/admin-executor.json', root / 'instances/admin-executor.json')
            self.change(root, 'modules/external-executor/module.json',
                        lambda doc: doc['requires'].append('interface/bash-runtime@1'))
            self.change(root, 'instances/admin-executor.json', lambda doc: doc['bindings'].update({
                'did:web:agentic.invalid#interface/bash-runtime@1': 'bash-admin'}))
            self.change(root, 'instances/agent-executor.json', lambda doc: doc['bindings'].update({
                'did:web:agentic.invalid#interface/bash-runtime@1': 'bash-agent'}))
            with self.assertRaisesRegex(ValueError, 'only unbound bootstrap executors'):
                expand(root)

    def test_method_receiver_must_be_bound_and_artifact_packaged(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            self.change(root, 'transitions/check-workspace/transition.json',
                        lambda doc: doc['operations'][0].update(instance='network'))
            with self.assertRaisesRegex(ValueError, 'unbound method receiver'):
                expand(root)
            shutil.copy(ROOT / 'transitions/check-workspace/transition.json',
                        root / 'transitions/check-workspace/transition.json')
            self.change(root, 'modules/tumbleweed-workspace/module.json',
                        lambda doc: doc['methods']['inspect'].update(artifact='../unreviewed.sh'))
            with self.assertRaisesRegex(ValueError, 'invalid method artifact'):
                expand(root)

    def test_dependency_cycle_is_rejected(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            # Managed runtimes cannot be cyclic; provided bootstrap executors are unbound.
            self.change(root, 'modules/bash-on-executor/module.json',
                        lambda doc: doc['requires'].append('interface/package-manager@1'))
            self.change(root, 'instances/bash-admin.json', lambda doc: doc['bindings'].update({
                'did:web:agentic.invalid#interface/package-manager@1': 'packages'}))
            self.change(root, 'instances/bash-agent.json', lambda doc: doc['bindings'].update({
                'did:web:agentic.invalid#interface/package-manager@1': 'packages'}))
            with self.assertRaisesRegex(ValueError, 'instance dependency cycle'):
                expand(root)


if __name__ == '__main__':
    unittest.main()
