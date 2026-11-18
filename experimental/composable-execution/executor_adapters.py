"""Explicit local and SSH implementations of executor.invoke.

Neither adapter authenticates policy claims in instance JSON. Both require an
independent authorizer, supplied by the operator, before any process is run.
No CLI or default allow-all policy is provided.
"""

import hashlib
from pathlib import Path
import re
import shlex
import subprocess


class ExecutorError(RuntimeError):
    pass


def prepare(root, call, authorize):
    """Load a packaged artifact and construct a target-runtime invocation."""
    if not callable(authorize):
        raise ValueError('an independent authorization callback is required')
    relative = call.get('artifact')
    if (not isinstance(relative, str)
            or not re.fullmatch(r'modules/[a-z][a-z0-9-]*/methods/[a-z][a-z0-9_.-]*', relative)):
        raise ExecutorError('artifact must be a packaged module method')
    root = Path(root).resolve(strict=True)
    artifact = root / relative
    if (any(part.is_symlink() for part in (artifact, *artifact.parents) if part != root
            and root in part.parents) or not artifact.is_file()
            or not artifact.resolve(strict=True).is_relative_to(root)):
        raise ExecutorError('method artifact is absent or linked')
    data = artifact.read_bytes()
    digest = hashlib.sha256(data).hexdigest()
    values = call.get('runtime_values')
    path = values.get('path') if isinstance(values, dict) else None
    if (not isinstance(path, str) or not path.startswith('/') or '\x00' in path
            or '\n' in path or '\r' in path):
        raise ExecutorError('invalid target runtime path')
    args = call.get('args')
    if (not isinstance(args, list) or any(not isinstance(arg, str) or '\x00' in arg
                                           for arg in args)):
        raise ExecutorError('invalid method arguments')
    if call.get('format') == 'text/x-bash':
        command = [path, '-s', '--', *args]
    elif call.get('format') == 'text/x-python':
        command = [path, '-', *args]
    else:
        raise ExecutorError('unsupported artifact format')
    if authorize(call, digest) is not True:
        raise PermissionError('executor policy rejected method artifact or arguments')
    return command, data


def result_of(completed):
    return {'exit_code': completed.returncode,
            'stdout': completed.stdout.decode('utf-8', errors='replace'),
            'stderr': completed.stderr.decode('utf-8', errors='replace')}


class LocalProcessExecutor:
    """Invoke a reviewed artifact using the current process's OS permissions."""

    def __init__(self, root, *, policy, runner=subprocess.run, timeout=600):
        self.root, self.policy, self.runner, self.timeout = root, policy, runner, timeout
        if (not callable(policy) or not callable(runner) or type(timeout) not in (int, float)
                or timeout <= 0):
            raise ValueError('local executor requires policy, runner and positive timeout')

    def invoke(self, call):
        command, data = prepare(self.root, call, self.policy)
        try:
            return result_of(self.runner(command, input=data, capture_output=True,
                                         timeout=self.timeout, check=False))
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ExecutorError('local method invocation failed') from error


class SSHExecutor:
    """Invoke via OpenSSH's non-interactive exec request on a POSIX Tumbleweed target."""

    def __init__(self, root, *, policy, host, user, port=22, identity_file=None,
                 runner=subprocess.run, timeout=600):
        if (not isinstance(host, str) or not re.fullmatch(r'[A-Za-z0-9][A-Za-z0-9.-]*', host)
                or not isinstance(user, str) or not re.fullmatch(r'[A-Za-z_][A-Za-z0-9_-]*', user)
                or type(port) is not int or not 1 <= port <= 65535
                or (identity_file is not None and (not isinstance(identity_file, str)
                    or not identity_file.startswith('/')))
                or not callable(policy) or not callable(runner)
                or type(timeout) not in (int, float) or timeout <= 0):
            raise ValueError('SSH executor requires host, user, policy and valid connection options')
        self.root, self.policy = root, policy
        self.host, self.user, self.port, self.identity_file = host, user, port, identity_file
        self.runner, self.timeout = runner, timeout

    def invoke(self, call):
        command, data = prepare(self.root, call, self.policy)
        ssh = ['ssh', '-T', '-o', 'BatchMode=yes', '-o', 'StrictHostKeyChecking=yes',
               '-o', 'NumberOfPasswordPrompts=0', '-o', 'ConnectTimeout=10',
               '-p', str(self.port)]
        if self.identity_file is not None:
            ssh += ['-i', self.identity_file]
        ssh += [f'{self.user}@{self.host}', shlex.join(command)]
        try:
            return result_of(self.runner(ssh, input=data, capture_output=True,
                                         timeout=self.timeout, check=False))
        except (OSError, subprocess.TimeoutExpired) as error:
            raise ExecutorError('SSH method invocation failed') from error
