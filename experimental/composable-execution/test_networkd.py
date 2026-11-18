"""Local-only tests: never contact a target or activate networking."""
import importlib.util
import io
from contextlib import redirect_stdout
from pathlib import Path
import tempfile
import unittest
from unittest.mock import patch

from plan import ROOT

artifact = ROOT / 'modules/tumbleweed-networkd/methods/stage.py'
spec = importlib.util.spec_from_file_location('networkd_stage', artifact)
stage = importlib.util.module_from_spec(spec)
spec.loader.exec_module(stage)


class NetworkdStagingTests(unittest.TestCase):
    def test_dhcp_and_static_content(self):
        dhcp = stage.render('eth0', 'AA:BB:CC:DD:EE:FF', 'dhcp', '', '', '')
        self.assertIn('[Match]\nName=eth0\nMACAddress=aa:bb:cc:dd:ee:ff\n', dhcp)
        self.assertIn('[Network]\nDHCP=ipv4\n', dhcp)
        self.assertNotIn('Gateway=', dhcp)
        static = stage.render('eth0', 'aa:bb:cc:dd:ee:ff', 'static', '192.0.2.10/24',
                              '192.0.2.1', '1.1.1.1 9.9.9.9')
        self.assertIn('Address=192.0.2.10/24\nGateway=192.0.2.1\n', static)
        self.assertIn('DNS=1.1.1.1\nDNS=9.9.9.9\n', static)
        self.assertTrue(static.startswith(stage.MARKER))

    def test_invalid_or_injectable_inputs_fail_before_writing(self):
        base = ['eth0', 'aa:bb:cc:dd:ee:ff', 'dhcp', '', '', '']
        for position, value in ((0, 'eth0\n[Network]'), (0, '..'), (1, 'invalid'),
                                (2, 'static'), (3, '192.0.2.10/24'), (5, '8.8.8.8')):
            with self.subTest(position=position, value=value):
                args = base.copy()
                args[position] = value
                with self.assertRaises(ValueError):
                    stage.render(*args)
        with self.assertRaises(ValueError):
            stage.render('eth0', base[1], 'static', '192.0.2.10/24', '192.0.2.1', '')
        with self.assertRaises(ValueError):
            stage.render('eth0', base[1], 'static', 'not-a-cidr', '192.0.2.1', '1.1.1.1')
        with self.assertRaises(ValueError):
            stage.render('eth0', base[1], 'static', '192.0.2.10/24', '192.0.2.1', 'bad\n[Match]')

    def test_target_identity_link_and_manager_preconditions(self):
        with tempfile.TemporaryDirectory() as tmp:
            root = Path(tmp)
            os_release = root / 'os-release'
            os_release.write_text('ID=opensuse-tumbleweed\n')
            net_dir = root / 'net'
            link = net_dir / 'eth0'
            link.mkdir(parents=True)
            (link / 'address').write_text('aa:bb:cc:dd:ee:ff\n')
            options = {'os_release': os_release, 'net_dir': net_dir,
                       'is_active': lambda unit: unit == 'systemd-networkd.service'}
            stage.require_target('eth0', 'aa:bb:cc:dd:ee:ff', **options)
            with self.assertRaisesRegex(ValueError, 'MAC'):
                stage.require_target('eth0', '00:00:00:00:00:00', **options)
            os_release.write_text('ID=debian\n')
            with self.assertRaisesRegex(ValueError, 'Tumbleweed'):
                stage.require_target('eth0', 'aa:bb:cc:dd:ee:ff', **options)
            os_release.write_text('ID=opensuse-tumbleweed\n')
            options['is_active'] = lambda unit: False
            with self.assertRaisesRegex(ValueError, 'not active'):
                stage.require_target('eth0', 'aa:bb:cc:dd:ee:ff', **options)
            options['is_active'] = lambda unit: unit in ('systemd-networkd.service', 'wicked.service')
            with self.assertRaisesRegex(ValueError, 'competing'):
                stage.require_target('eth0', 'aa:bb:cc:dd:ee:ff', **options)

    def test_atomic_stage_refuses_unmanaged_or_linked_files(self):
        content = stage.render('eth0', 'aa:bb:cc:dd:ee:ff', 'dhcp', '', '', '')
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            path = stage.stage_file(folder, content)
            self.assertEqual(path.read_text(), content)
            self.assertEqual(path.stat().st_mode & 0o777, 0o644)
            stage.stage_file(folder, content)
            self.assertEqual(list(folder.iterdir()), [path])
            path.write_text('[Network]\nDHCP=no\n')
            with self.assertRaisesRegex(ValueError, 'unmanaged'):
                stage.stage_file(folder, content)
            self.assertEqual(path.read_text(), '[Network]\nDHCP=no\n')
            path.unlink()
            path.symlink_to(folder / 'unmanaged')
            with self.assertRaisesRegex(ValueError, 'linked'):
                stage.stage_file(folder, content)
            self.assertTrue(path.is_symlink())

    def test_main_stages_only_with_injected_preconditions(self):
        args = ['eth0', 'aa:bb:cc:dd:ee:ff', 'dhcp', '', '', '']
        with tempfile.TemporaryDirectory() as tmp:
            folder = Path(tmp)
            with (patch.object(stage, 'NETWORK_DIR', folder),
                  patch.object(stage, 'require_target') as preflight,
                  patch.object(stage.subprocess, 'run') as systemctl,
                  redirect_stdout(io.StringIO()) as output):
                stage.main(args)
            preflight.assert_called_once_with('eth0', args[1])
            systemctl.assert_not_called()  # no reload/reconfigure/activation in staging
            self.assertIn('NOT activated', output.getvalue())
            self.assertTrue((folder / stage.NETWORK_FILE).is_file())


if __name__ == '__main__':
    unittest.main()
