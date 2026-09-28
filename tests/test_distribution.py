"""Check CLI distribution without hardware, Qt or desktop mutations."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest

from barracuda_status import i18n

ROOT = Path(__file__).resolve().parents[1]


class DistributionTests(unittest.TestCase):
    def tearDown(self):
        i18n.set_language('en')

    def test_all_cli_strings_have_spanish_translations(self):
        for path in (ROOT / 'barracuda_status').glob('*.py'):
            for node in ast.walk(ast.parse(path.read_text())):
                if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                        and node.func.id == 'tr' and node.args
                        and isinstance(node.args[0], ast.Constant)):
                    self.assertIn(node.args[0].value, i18n.SPANISH)

    def test_languages(self):
        for language, expected in [('en', 'Pairing cancelled'),
                                   ('es', 'Emparejamiento cancelado')]:
            i18n.set_language(language)
            self.assertEqual(i18n.tr('Pairing cancelled'), expected)
            self.assertIn('error', i18n.tr('Pairing failed: {error}', error='error'))

    def test_default_language_ignores_desktop_locale(self):
        result = subprocess.check_output(
            [sys.executable, '-c', 'from barracuda_status.i18n import tr; '
             'print(tr("Pairing cancelled"))'], cwd=ROOT,
            env={**os.environ, 'LANG': 'es_ES.UTF-8'}, text=True)
        self.assertEqual(result.strip(), 'Pairing cancelled')

    def test_module_needs_no_third_party_packages(self):
        result = subprocess.run([sys.executable, '-S', '-m', 'barracuda_status', '--help'],
                                cwd=ROOT, check=True, capture_output=True, text=True)
        self.assertIn('barracuda-pair', result.stdout)

    def test_install_in_isolated_home(self):
        with tempfile.TemporaryDirectory(prefix='barracuda test ') as directory:
            home = Path(directory)
            env = {**os.environ, 'HOME': directory, 'XDG_DATA_HOME': str(home / 'data'),
                   'XDG_CONFIG_HOME': str(home / 'config')}
            subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'),
                            '--language', 'es'], env=env, check=True, capture_output=True)
            launcher = home / '.local/bin/barracuda-pair'
            result = subprocess.run([str(launcher), '--help'], cwd=directory, env=env,
                                    check=True, capture_output=True, text=True)
            self.assertTrue(result.stdout.startswith('usage: barracuda-pair'))
            self.assertIn('--scan', result.stdout)
            self.assertEqual(list(launcher.parent.iterdir()), [launcher])
            self.assertFalse((home / 'config').exists())
            self.assertFalse((home / 'data/applications').exists())
            self.assertFalse((home / 'data/barracuda-pair/barracuda_status/app.py').exists())
