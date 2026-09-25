"""Keep the patches in upstream/ in sync with the sources in this repository."""
from pathlib import Path
import shutil
import subprocess
import tempfile
import unittest

ROOT = Path(__file__).resolve().parents[1]
UPSTREAM = ROOT / 'upstream'
DRIVER = ROOT / 'kernel' / 'hid-razer-barracuda'
FILES = ('hid-razer-barracuda.c', 'hid-razer-barracuda-test.c')


def added_lines(patch):
    return [line for line in patch.read_text().splitlines()
            if line.startswith('+') and not line.startswith('+++')]


class UpstreamSeriesTests(unittest.TestCase):
    def test_hid_series_matches_driver_sources(self):
        if shutil.which('git') is None:
            self.skipTest('git is required to apply the series')
        series = sorted((UPSTREAM / 'hid').glob('0[0-9][0-9][1-9]-*.patch'))
        self.assertEqual(len(series), 2)
        with tempfile.TemporaryDirectory() as directory:
            # The driver files are new in the series, so they apply to an empty tree.
            for patch in series:
                subprocess.run(['git', 'apply', '--include=drivers/hid/hid-razer-barracuda*',
                                str(patch)], cwd=directory, check=True)
            for name in FILES:
                applied = Path(directory, 'drivers/hid', name).read_text()
                self.assertEqual(applied, (DRIVER / name).read_text(), name)

    def test_patches_are_ready_for_signoff(self):
        for patch in sorted(UPSTREAM.glob('*/0*.patch')):
            text = patch.read_text()
            # Only the submitter can certify the DCO.
            self.assertNotIn('Signed-off-by:', text, patch.name)
            self.assertNotIn('***', text, patch.name)
            if 'cover-letter' not in patch.name:
                self.assertIn('Assisted-by: LLM', text, patch.name)

    def test_alsa_quirk_matches_dkms_patch(self):
        upstream = next((UPSTREAM / 'alsa').glob('0001-*.patch'))
        local = next((ROOT / 'kernel' / 'snd-usb-audio').glob('*.patch'))
        self.assertEqual(added_lines(upstream), added_lines(local))


if __name__ == '__main__':
    unittest.main()
