"""Check CLI distribution without hardware, Qt or desktop mutations."""
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]


class DistributionTests(unittest.TestCase):
    def test_cli_has_no_language_option(self):
        for module in ('pairing', 'control', 'headset'):
            result = subprocess.run([sys.executable, '-m', f'barracuda_pair.{module}', '--help'],
                                    cwd=ROOT, check=True, capture_output=True, text=True)
            self.assertNotIn('--language', result.stdout)
        self.assertFalse((ROOT / 'barracuda_pair/i18n.py').exists())

    def test_module_needs_no_third_party_packages(self):
        result = subprocess.run([sys.executable, '-S', '-m', 'barracuda_pair', '--help'],
                                cwd=ROOT, check=True, capture_output=True, text=True)
        self.assertIn('barracuda-pair', result.stdout)

    def test_install_in_isolated_home(self):
        with tempfile.TemporaryDirectory(prefix='barracuda test ') as directory:
            home = Path(directory)
            env = {**os.environ, 'HOME': directory, 'XDG_DATA_HOME': str(home / 'data'),
                   'XDG_CONFIG_HOME': str(home / 'config')}
            stale = home / 'data/barracuda-pair/barracuda_pair/i18n.py'
            stale.parent.mkdir(parents=True)
            stale.write_text('')
            subprocess.run([sys.executable, str(ROOT / 'scripts/install.py')],
                           env=env, check=True, capture_output=True)
            self.assertFalse(stale.exists())
            launcher = home / '.local/bin/barracuda-pair'
            result = subprocess.run([str(launcher), '--help'], cwd=directory, env=env,
                                    check=True, capture_output=True, text=True)
            self.assertTrue(result.stdout.startswith('usage: barracuda-pair'))
            self.assertIn('--scan', result.stdout)
            self.assertEqual(set(launcher.parent.iterdir()),
                             {launcher, launcher.with_name('barracuda-power'), launcher.with_name('barracuda-headset')})
            native = subprocess.run([str(launcher.with_name('barracuda-headset')), '--help'],
                                    cwd=directory, env=env, check=True, capture_output=True, text=True)
            self.assertIn('--request', native.stdout)
            power = subprocess.run([str(launcher.with_name('barracuda-power')), '--help'],
                                   cwd=directory, env=env, check=True, capture_output=True, text=True)
            self.assertIn('--off', power.stdout)
            self.assertFalse((home / 'config').exists())
            self.assertFalse((home / 'data/applications').exists())
            self.assertFalse((home / 'data/barracuda-pair/barracuda_pair/app.py').exists())
