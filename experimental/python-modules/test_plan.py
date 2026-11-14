import subprocess
import unittest
from dataclasses import dataclass
from pathlib import PurePosixPath

from deployment import Instance
from instances import DEPLOYMENT, host, interactive
from interfaces_v1 import Module, OperatingSystem, Target
from modules import LinuxLocalAccount, SCRIPTS
from plan import expand, render


class PythonModuleTests(unittest.TestCase):
    def test_pure_expansion_resolves_shell_path_before_target_execution(self):
        tasks = expand(DEPLOYMENT)
        self.assertEqual([task.instance for task in tasks], ['host', 'interactive', 'agentic'])
        self.assertEqual([task.module for task in tasks],
                         ['OpenSuseTumbleweed', 'ZshOnTumbleweed', 'LinuxLocalAccount'])
        self.assertEqual(tasks[1].args, ('/usr/bin/zsh',))
        self.assertEqual(tasks[2].args, ('agentic', '/usr/bin/zsh'))
        self.assertEqual(tasks[2].dependencies, ('host', 'interactive'))
        self.assertNotIn('agentic', (SCRIPTS / 'account-ensure.sh').read_text())
        self.assertNotIn('/usr/bin/zsh', (SCRIPTS / 'account-ensure.sh').read_text())
        rendered = render(tasks)
        self.assertIn("sh -s -- agentic /usr/bin/zsh <<'AGENTIC_TASK_2'", rendered)
        self.assertIn('AGENTIC_CONSOLE_VERIFIED', rendered)
        subprocess.run(['sh', '-n'], input=rendered, text=True, check=True)

    def test_two_configured_accounts_reuse_shell_and_account_class(self):
        reviewer = Instance('reviewer', LinuxLocalAccount('reviewer', host.module, interactive.module))
        tasks = expand((*DEPLOYMENT, reviewer))
        self.assertEqual([task.instance for task in tasks], ['host', 'interactive', 'agentic', 'reviewer'])
        self.assertEqual(tasks[-1].args, ('reviewer', '/usr/bin/zsh'))
        self.assertEqual(tasks[-1].script, tasks[-2].script)

    def test_shell_implementation_can_change_without_changing_account(self):
        @dataclass(frozen=True)
        class AlternativeShell:
            os: OperatingSystem

            def path(self) -> PurePosixPath:
                return PurePosixPath('/opt/alternative/shell')

            def dependencies(self) -> tuple[Module, ...]:
                return (self.os,)

            def ensure(self, target: Target) -> None:
                # Test-only stand-in: do not execute its recorded script on a host.
                target.run(SCRIPTS / 'zsh-ensure.sh', (str(self.path()),))

        shell = Instance('alternative', AlternativeShell(host.module))
        account = Instance('reviewer', LinuxLocalAccount('reviewer', host.module, shell.module))
        tasks = expand((account, shell, host))
        self.assertEqual([task.instance for task in tasks], ['host', 'alternative', 'reviewer'])
        self.assertEqual(tasks[-1].args, ('reviewer', '/opt/alternative/shell'))

    def test_invalid_account_name_and_relative_shell_path_fail_before_execution(self):
        root_account = Instance('unsafe', LinuxLocalAccount('root', host.module, interactive.module))
        with self.assertRaisesRegex(ValueError, 'invalid unprivileged account name'):
            expand((host, interactive, root_account))

        @dataclass(frozen=True)
        class RelativeShell:
            os: OperatingSystem

            def path(self) -> PurePosixPath:
                return PurePosixPath('relative/shell')

            def dependencies(self) -> tuple[Module, ...]:
                return (self.os,)

            def ensure(self, target: Target) -> None:
                target.run(SCRIPTS / 'zsh-ensure.sh', (str(self.path()),))

        shell = Instance('relative', RelativeShell(host.module))
        account = Instance('tester', LinuxLocalAccount('tester', host.module, shell.module))
        with self.assertRaisesRegex(ValueError, 'path must be absolute'):
            expand((host, shell, account))

    def test_unbound_dependency_and_cycle_fail_during_expansion(self):
        unbound = Instance('orphan', LinuxLocalAccount('orphan', host.module, interactive.module))
        with self.assertRaisesRegex(ValueError, 'unbound dependency'):
            expand((host, unbound))

        class Loop:
            def dependencies(self) -> tuple[Module, ...]:
                return (self,)

            def ensure(self, target: Target) -> None:
                target.run(SCRIPTS / 'opensuse-ensure.sh')

        with self.assertRaisesRegex(ValueError, 'dependency cycle'):
            expand((Instance('loop', Loop()),))


if __name__ == '__main__':
    unittest.main()
