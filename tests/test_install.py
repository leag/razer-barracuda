"""User installer steps with mocked commands; nothing runs as root."""
from contextlib import redirect_stdout
import importlib.util
import io
from pathlib import Path
import sys
import tempfile
import unittest
from unittest.mock import patch

SCRIPTS = Path(__file__).resolve().parents[1] / 'scripts'
sys.path.insert(0, str(SCRIPTS))
SPEC = importlib.util.spec_from_file_location('install', SCRIPTS / 'install.py')
installer = importlib.util.module_from_spec(SPEC)
SPEC.loader.exec_module(installer)


class InstallerTests(unittest.TestCase):
    def steps(self, root, driver=False, native=False):
        with patch.object(installer, 'driver_installed', return_value=driver), \
                patch.object(installer, 'pipewire_wireless_support', return_value=native):
            return installer.system_steps(Path(root))

    def test_checkout_needs_rule_driver_and_quirk(self):
        with tempfile.TemporaryDirectory() as root:
            steps = self.steps(root)
        self.assertEqual(steps[0][-1], '/etc/udev/rules.d/99-razer-barracuda.rules')
        self.assertTrue(steps[1][-1].endswith('scripts/install_dkms.py'))
        self.assertTrue(steps[2][-1].endswith('scripts/install_snd_usb_audio_quirk.py'))

    def test_installed_driver_and_native_pipewire_are_skipped(self):
        with tempfile.TemporaryDirectory() as root:
            steps = self.steps(root, driver=True, native=True)
        # Without the driver installer, the new rule still needs a reload.
        self.assertEqual([step[0] for step in steps], ['install', 'udevadm'])

    def test_package_provided_parts_are_left_to_packages(self):
        with tempfile.TemporaryDirectory() as directory:
            root = Path(directory)
            (root / 'usr/lib/udev/rules.d').mkdir(parents=True)
            (root / 'usr/lib/udev/rules.d/99-razer-barracuda.rules').write_text('')
            (root / 'usr/share/hid-razer-barracuda').mkdir(parents=True)
            self.assertEqual(self.steps(root), [])

    def test_system_steps_share_one_pkexec_prompt(self):
        steps = [['install', 'a b', '/etc/x'], ['python3', '/c/install_dkms.py']]
        with patch.object(installer.shutil, 'which', return_value='/usr/bin/pkexec'), \
                patch.object(installer.subprocess, 'run') as run, redirect_stdout(io.StringIO()):
            installer.install_system(steps)
        run.assert_called_once()
        command = run.call_args.args[0]
        self.assertEqual(command[:3], ['pkexec', '/bin/sh', '-c'])
        self.assertEqual(command[3], "set -e\ninstall 'a b' /etc/x\npython3 /c/install_dkms.py")

    def test_without_pkexec_the_sudo_commands_are_printed(self):
        with patch.object(installer.shutil, 'which', return_value=None), \
                patch.object(installer.subprocess, 'run') as run:
            with self.assertRaisesRegex(SystemExit, 'sudo python3 /c/install_dkms.py'):
                installer.install_system([['python3', '/c/install_dkms.py']])
        run.assert_not_called()

    def test_path_detection(self):
        local = Path.home() / '.local/bin'
        self.assertTrue(installer.on_path(local, '/usr/bin:~/.local/bin'))
        self.assertFalse(installer.on_path(local, '/usr/bin'))


if __name__ == '__main__':
    unittest.main()
