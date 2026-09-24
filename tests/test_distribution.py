"""Check translation coverage and installation without touching the desktop."""
import ast
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch

from barracuda_status import app, i18n

ROOT = Path(__file__).resolve().parent.parent


class DistributionTests(unittest.TestCase):
    def tearDown(self):
        i18n.set_language('en')

    def test_all_ui_strings_have_spanish_translations(self):
        for path in (ROOT / 'barracuda_status').glob('*.py'):
            for node in ast.walk(ast.parse(path.read_text())):
                if (isinstance(node, ast.Call) and isinstance(node.func, ast.Name)
                        and node.func.id == 'tr' and node.args
                        and isinstance(node.args[0], ast.Constant)):
                    self.assertIn(node.args[0].value, i18n.SPANISH)

    def test_both_languages_and_formatting(self):
        os.environ.setdefault('QT_QPA_PLATFORM', 'offscreen')
        qt = app.QApplication.instance() or app.QApplication([])
        for language, label in [('en', 'Connected'), ('es', 'Enlazados')]:
            i18n.set_language(language)
            with patch.object(app.HidReader, 'start'), patch.object(app.AudioWorker, 'start'):
                tray = app.Tray()
                tray.update_status(True)
                self.assertEqual(tray.status_action.text(), label)
                tray.close()
            self.assertIn('test error', i18n.tr('Could not switch output: {error}', error='test error'))

    def test_default_language_ignores_desktop_locale(self):
        env = {**os.environ, 'LANG': 'es_ES.UTF-8'}
        result = subprocess.check_output([sys.executable, '-c',
                    'from barracuda_status.i18n import tr; print(tr("Connected"))'],
                    cwd=ROOT, env=env, text=True)
        self.assertEqual(result.strip(), 'Connected')

    def test_packaged_icons(self):
        qt = app.QApplication.instance() or app.QApplication([])
        with patch.object(app, 'ICON_DIR', Path('/nonexistent')):
            for emblem in ('emblem-ok', 'emblem-warning', 'emblem-error', 'dialog-question'):
                self.assertFalse(app.status_icon(emblem).pixmap(32, 32).isNull())

    def test_install_in_isolated_home(self):
        with tempfile.TemporaryDirectory(prefix='barracuda test ') as directory:
            home = Path(directory)
            env = {**os.environ, 'HOME': directory, 'XDG_DATA_HOME': str(home / 'data'),
                   'XDG_CONFIG_HOME': str(home / 'config')}
            subprocess.run([sys.executable, str(ROOT / 'scripts/install.py'),
                            '--autostart', '--language', 'es'], env=env, check=True,
                           capture_output=True, text=True)
            launcher = home / '.local/bin/barracuda-status'
            result = subprocess.run([str(launcher), '--help'], cwd=directory, env=env,
                                    check=True, capture_output=True, text=True)
            self.assertIn('--language', result.stdout)
            result = subprocess.run([str(home / '.local/bin/barracuda-pair'), '--help'],
                                    cwd=directory, env=env, check=True, capture_output=True,
                                    text=True)
            self.assertIn('--scan', result.stdout)
            desktop = (home / 'config/autostart/org.razer.BarracudaStatus.desktop').read_text()
            self.assertIn('--language es', desktop)
            self.assertIn(f'Exec="{launcher}"', desktop)
