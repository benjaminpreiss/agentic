"""Exercise real adapter construction with a fake OS process runner; no target calls."""
import hashlib
import json
from pathlib import Path
import shlex
import shutil
import subprocess
import tempfile
import unittest

from dispatch import configured_executors, run_configured
from executor_adapters import ExecutorError, LocalProcessExecutor, SSHExecutor
from plan import ROOT, expand


class RecordingProcess:
    def __init__(self):
        self.calls = []

    def __call__(self, command, **options):
        self.calls.append((command, options))
        return subprocess.CompletedProcess(command, 0, stdout=b'ok', stderr=b'')


class ExecutorAdapterTests(unittest.TestCase):
    def test_ssh_executor_invokes_bash_and_python_with_strict_host_authentication(self):
        process = RecordingProcess()
        settings = {name: {'host': 'vm.example.invalid', 'user': 'operator',
                           'policy': lambda call, digest: True, 'runner': process}
                    for name in ('admin-executor', 'agent-executor')}
        results = run_configured(settings)
        self.assertEqual(len(results), 5)
        self.assertEqual(len(process.calls), 5)
        ssh, options = process.calls[0]
        self.assertEqual(ssh[0], 'ssh')
        self.assertIn('StrictHostKeyChecking=yes', ssh)
        self.assertIn('BatchMode=yes', ssh)
        self.assertIn('operator@vm.example.invalid', ssh)
        self.assertIn('/usr/bin/bash -s --', ssh[-1])
        self.assertEqual(options['input'], (ROOT / 'modules/opensuse-tumbleweed/methods/inspect-identity.sh').read_bytes())
        remote = process.calls[-2][0][-1]
        self.assertEqual(shlex.split(remote), ['/usr/bin/python3', '-', 'vm-uplink',
                                               '00:00:00:00:00:00', 'dhcp', '', '', ''])

    def test_ssh_quotes_structured_arguments_without_running_a_shell_here(self):
        process = RecordingProcess()
        call = next(step for step in expand() if step['instance'] == 'host')['calls'][0].copy()
        dangerous = "one'; touch /tmp/never-run; '"
        call['args'] = [dangerous]
        adapter = SSHExecutor(ROOT, policy=lambda c, sha: True, runner=process,
                              host='vm.example.invalid', user='operator')
        adapter.invoke(call)
        self.assertEqual(shlex.split(process.calls[0][0][-1]),
                         ['/usr/bin/bash', '-s', '--', dangerous])

    def test_local_executor_uses_selected_target_runtime_and_artifact_bytes(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            for folder in ('interfaces', 'modules', 'instances', 'transitions'):
                shutil.copytree(ROOT / folder, root / folder)
            shutil.copy(ROOT / 'requests.json', root / 'requests.json')
            for name in ('admin-executor', 'agent-executor'):
                file = root / f'instances/{name}.json'
                doc = json.loads(file.read_text())
                doc['module'] = 'did:web:agentic.invalid#module/local-process-executor@1'
                file.write_text(json.dumps(doc))
            process = RecordingProcess()
            settings = {name: {'policy': lambda call, digest: True, 'runner': process}
                        for name in ('admin-executor', 'agent-executor')}
            results = run_configured(settings, root)
            self.assertEqual(len(results), 5)
            self.assertEqual(process.calls[0][0], ['/usr/bin/bash', '-s', '--'])
            self.assertEqual(process.calls[-2][0], ['/usr/bin/python3', '-',
                                                   'vm-uplink', '00:00:00:00:00:00', 'dhcp', '', '', ''])
            self.assertEqual(process.calls[-2][1]['input'],
                             (root / 'modules/tumbleweed-networkd/methods/stage.py').read_bytes())

    def test_policy_receives_digest_and_rejection_runs_no_process(self):
        process = RecordingProcess()
        call = next(step for step in expand() if step['instance'] == 'host')['calls'][0]
        artifact = ROOT / call['artifact']
        digest = hashlib.sha256(artifact.read_bytes()).hexdigest()
        adapter = LocalProcessExecutor(ROOT, policy=lambda c, sha: sha == digest,
                                       runner=process)
        self.assertEqual(adapter.invoke(call)['exit_code'], 0)
        self.assertEqual(len(process.calls), 1)
        denying = LocalProcessExecutor(ROOT, policy=lambda c, sha: False, runner=process)
        with self.assertRaises(PermissionError):
            denying.invoke(call)
        self.assertEqual(len(process.calls), 1)
        with self.assertRaises(ValueError):
            LocalProcessExecutor(ROOT, policy=None, runner=process)

    def test_artifact_path_and_ssh_destination_validation(self):
        process = RecordingProcess()
        call = next(step for step in expand() if step['instance'] == 'host')['calls'][0].copy()
        adapter = SSHExecutor(ROOT, policy=lambda c, sha: True,
                              runner=process, host='vm.example.invalid', user='operator')
        call['artifact'] = '../not-reviewed.sh'
        with self.assertRaises(ExecutorError):
            adapter.invoke(call)
        self.assertEqual(process.calls, [])
        with self.assertRaises(ValueError):
            SSHExecutor(ROOT, policy=lambda c, sha: True, runner=process,
                        host='-oProxyCommand=bad', user='operator')
        with self.assertRaises(ValueError):
            configured_executors({'admin-executor': {'host': 'vm.example.invalid', 'user': 'operator',
                                                    'policy': lambda c, sha: True, 'runner': process}})


if __name__ == '__main__':
    unittest.main()
