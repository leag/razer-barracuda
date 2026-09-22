"""Exercise the exact kernel stream decoder without loading a module."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parent.parent


class KernelProtocolTests(unittest.TestCase):
    def test_c_decoder(self):
        compiler = shutil.which('cc')
        if compiler is None:
            self.skipTest('A C compiler is required for kernel decoder tests')
        with tempfile.TemporaryDirectory() as directory:
            binary = Path(directory) / 'test-protocol'
            subprocess.run([compiler, '-std=c11', '-Wall', '-Wextra', '-Werror',
                            '-fsanitize=address,undefined', '-g',
                            str(ROOT / 'kernel/hid-barracuda/test-protocol.c'),
                            '-o', str(binary)], check=True, capture_output=True, text=True)
            result = subprocess.run([str(binary)], check=True, capture_output=True, text=True)
            self.assertIn('tests passed', result.stdout)
