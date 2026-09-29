#!/usr/bin/env python3
"""Install the pairing CLI for the current user, without desktop integration."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=('en', 'es'), default='en')
    parser.add_argument('--audio-controls', action='store_true',
                        help='also install the optional barracuda-audio helper; does not enable effects')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    target = data / 'barracuda-pair'
    package = target / 'barracuda_pair'
    package.mkdir(parents=True, exist_ok=True)
    for name in ('__init__.py', '__main__.py', 'pairing.py', 'i18n.py'):
        shutil.copy2(root / 'barracuda_pair' / name, package / name)
    binary = Path.home() / '.local/bin/barracuda-pair'
    binary.parent.mkdir(parents=True, exist_ok=True)
    code = ('import sys; sys.path.insert(0, ' + repr(str(target)) +
            '); from barracuda_pair.pairing import main; raise SystemExit(main())')
    binary.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -c ' +
                      shlex.quote(code) + ' --language ' + args.language + ' "$@"\n')
    binary.chmod(0o755)
    if args.audio_controls:
        for name in ('audio.py', 'audio_presets.py'):
            shutil.copy2(root / 'barracuda_pair' / name, package / name)
        license_dir = target / 'LICENSES'
        license_dir.mkdir(exist_ok=True)
        shutil.copy2(root / 'LICENSES/TarikTopalovic-MIT.txt', license_dir)
        audio_binary = binary.with_name('barracuda-audio')
        audio_code = ('import sys; sys.path.insert(0, ' + repr(str(target)) +
                      '); from barracuda_pair.audio import main; raise SystemExit(main())')
        audio_binary.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -c ' +
                                shlex.quote(audio_code) + ' "$@"\n')
        audio_binary.chmod(0o755)
    print(f'Installed {binary}. No desktop or audio settings were changed.')


if __name__ == '__main__':
    main()
