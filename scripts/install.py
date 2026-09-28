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
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    target = data / 'barracuda-pair'
    package = target / 'barracuda_status'
    package.mkdir(parents=True, exist_ok=True)
    for name in ('__init__.py', '__main__.py', 'pairing.py', 'i18n.py'):
        shutil.copy2(root / 'barracuda_status' / name, package / name)
    binary = Path.home() / '.local/bin/barracuda-pair'
    binary.parent.mkdir(parents=True, exist_ok=True)
    code = ('import sys; sys.path.insert(0, ' + repr(str(target)) +
            '); from barracuda_status.pairing import main; raise SystemExit(main())')
    binary.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -c ' +
                      shlex.quote(code) + ' --language ' + args.language + ' "$@"\n')
    binary.chmod(0o755)
    print(f'Installed {binary}. No desktop or audio settings were changed.')


if __name__ == '__main__':
    main()
