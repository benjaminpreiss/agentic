"""Method composition using recording adapters; never executes a target artifact."""
import json
from pathlib import Path
import shutil
import tempfile
import unittest

from dispatch import InvocationFailed, run_requested
from plan import ROOT


class RecordingExecutor:
    def __init__(self, result=None):
        self.calls = []
        self.result = result or {'exit_code': 0, 'stdout': ''}

    def invoke(self, call):
        self.calls.append(call)
        return self.result


class DispatchTests(unittest.TestCase):
    def copy(self, root):
        for folder in ('interfaces', 'modules', 'instances', 'transitions'):
            shutil.copytree(ROOT / folder, root / folder)
        shutil.copy(ROOT / 'requests.json', root / 'requests.json')
        return root

    def test_nested_runtime_method_calls_bound_executor(self):
        admin, agent = RecordingExecutor(), RecordingExecutor()
        observations = run_requested({'admin-executor': admin, 'agent-executor': agent})
        self.assertEqual([call['receiver'] for call in admin.calls],
                         ['host', 'packages', 'network', 'network'])
        self.assertEqual([call['receiver'] for call in agent.calls], ['workspace'])
        self.assertEqual([call['runtime'] for call in admin.calls[-2:]],
                         ['bash-admin', 'python-admin'])
        self.assertEqual(admin.calls[-1]['method'], 'configure')
        self.assertEqual(admin.calls[-1]['args'], ['vm-uplink', '00:00:00:00:00:00', 'dhcp', '', '', ''])
        self.assertEqual(len(observations), 5)

    def test_runtime_dispatch_follows_changed_instance_binding(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            executor = root / 'instances/agent-executor.json'
            doc = json.loads(executor.read_text())
            doc['grants'].append('network-read')
            executor.write_text(json.dumps(doc))
            network = root / 'instances/network.json'
            doc = json.loads(network.read_text())
            doc['bindings']['did:web:agentic.invalid#interface/bash-runtime@1'] = 'bash-agent'
            network.write_text(json.dumps(doc))
            admin, agent = RecordingExecutor(), RecordingExecutor()
            run_requested({'admin-executor': admin, 'agent-executor': agent}, root)
            self.assertEqual([call['method'] for call in agent.calls], ['inspect', 'inspect'])
            self.assertEqual(admin.calls[-1]['method'], 'configure')

    def test_no_adapter_is_chosen_implicitly_or_invoked_before_preflight(self):
        admin = RecordingExecutor()
        with self.assertRaisesRegex(ValueError, 'missing bound executor adapter: agent-executor'):
            run_requested({'admin-executor': admin})
        self.assertEqual(admin.calls, [])

    def test_failure_stops_later_methods(self):
        admin, agent = RecordingExecutor({'exit_code': 1}), RecordingExecutor()
        with self.assertRaisesRegex(InvocationFailed, 'host.inspect_identity'):
            run_requested({'admin-executor': admin, 'agent-executor': agent})
        self.assertEqual(len(admin.calls), 1)
        self.assertEqual(agent.calls, [])

    def test_old_delegate_marker_is_no_longer_an_implementation(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            file = root / 'modules/tumbleweed-bash/module.json'
            doc = json.loads(file.read_text())
            doc['methods']['run'] = {'implementation': 'delegate',
                                     'via': 'interface/executor@1', 'accepts': ['text/x-bash']}
            file.write_text(json.dumps(doc))
            with self.assertRaisesRegex(ValueError, 'invalid method implementation'):
                run_requested({'admin-executor': RecordingExecutor(),
                               'agent-executor': RecordingExecutor()}, root)

    def test_runtime_calls_must_reference_bound_interface_method(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = self.copy(Path(tmp))
            file = root / 'modules/tumbleweed-bash/module.json'
            doc = json.loads(file.read_text())
            doc['methods']['run']['calls'][0]['via'] = 'interface/os@1'
            file.write_text(json.dumps(doc))
            with self.assertRaisesRegex(ValueError, 'invalid runtime calls'):
                run_requested({'admin-executor': RecordingExecutor(),
                               'agent-executor': RecordingExecutor()}, root)


if __name__ == '__main__':
    unittest.main()
