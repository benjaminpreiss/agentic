"""Interpret reviewed runtime methods with explicitly configured executor modules.

No CLI, credentials or default policy is supplied. Calling run_configured with
real settings crosses the execution seam and can change a target.
"""

import json
from pathlib import Path

from executor_adapters import LocalProcessExecutor, SSHExecutor
from plan import ROOT, catalog, expand, reference


class InvocationFailed(RuntimeError):
    """A bound executor rejected or failed a requested method invocation."""


def configured_executors(settings, root=ROOT):
    """Construct real adapters for provided executor modules using out-of-band settings.

    Settings must include an independent `policy` callable per executor. SSH
    credentials/host details are supplied by the caller, never instance JSON.
    """
    if not isinstance(settings, dict):
        raise ValueError('executor settings must be keyed by instance ID')
    docs = catalog(root)
    adapters = {}
    for file in sorted((Path(root) / 'instances').glob('*.json')):
        instance = json.loads(file.read_text())
        if not instance.get('provided', False):
            continue
        name = instance['id']
        mod = docs['module'][reference(instance['module'], 'module')]
        implementation = mod['methods']['invoke']['adapter']
        options = settings.get(name)
        if not isinstance(options, dict):
            raise ValueError(f'missing executor settings: {name}')
        if implementation == 'local-process':
            adapters[name] = LocalProcessExecutor(root, **options)
        elif implementation == 'ssh':
            adapters[name] = SSHExecutor(root, **options)
        else:
            raise ValueError(f'unsupported executor implementation: {name}')
    if set(settings) != set(adapters):
        raise ValueError('executor settings do not match provided instances')
    return adapters


def run_configured(settings, root=ROOT):
    """Run explicitly requested transitions using concrete configured executors."""
    return run_requested(configured_executors(settings, root), root)


def run_requested(executors, root=ROOT):
    """Call runtime.run -> bound executor.invoke for each explicitly requested operation.

    Executor adapters implement invoke(call) -> {"exit_code": int, ...} and must
    enforce authority independently. Results are returned to this invocation only;
    nothing is persisted or substituted into later static plan arguments.
    """
    steps = expand(root)
    if not isinstance(executors, dict):
        raise ValueError('executor adapters must be injected by instance ID')
    # Refuse missing or malformed adapters before starting any operation.
    for step in steps:
        for call in step['calls']:
            route = call['invocation']
            if (route['instance'] != call['runtime'] or route['method'] != 'run'
                    or len(route['calls']) != 1 or route['calls'][0] != {
                        'instance': call['executor'], 'method': 'invoke'}):
                raise ValueError('invalid runtime invocation route')
            adapter = executors.get(call['executor'])
            if not callable(getattr(adapter, 'invoke', None)):
                raise ValueError(f"missing bound executor adapter: {call['executor']}")
    observations = []
    for step in steps:
        for call in step['calls']:
            adapter = executors[call['invocation']['calls'][0]['instance']]
            result = adapter.invoke({key: value for key, value in call.items() if key != 'invocation'})
            if (not isinstance(result, dict) or type(result.get('exit_code')) is not int):
                raise InvocationFailed(f"invalid executor result: {call['receiver']}.{call['method']}")
            if result['exit_code'] != 0:
                raise InvocationFailed(f"method failed: {call['receiver']}.{call['method']}")
            observations.append({'instance': step['instance'], 'method': call['method'],
                                 'result': result})
    return observations
