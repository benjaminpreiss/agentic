"""Interpret reviewed runtime method calls with explicitly injected executors.

No production executor, local process runner, SSH transport or CLI is supplied here.
An injected executor must authenticate its target and enforce its own policy;
fixture target/grant labels are never authorization.
"""

from plan import ROOT, expand


class InvocationFailed(RuntimeError):
    """A bound executor rejected or failed a requested method invocation."""


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
