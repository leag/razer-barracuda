#!/usr/bin/env python3
"""Install a self-contained user copy using the current Python interpreter."""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import sys


def main():
    parser = argparse.ArgumentParser(description=__doc__)
    parser.add_argument('--language', choices=('en', 'es'), default='en')
    parser.add_argument('--autostart', action='store_true')
    parser.add_argument('--wireplumber-analog-only', action='store_true',
                        help='limit the dongle to analog profiles (for jack detection)')
    args = parser.parse_args()
    root = Path(__file__).resolve().parent.parent
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    config = Path(os.environ.get('XDG_CONFIG_HOME', Path.home() / '.config'))
    target = data / 'barracuda-status'
    binary = Path.home() / '.local/bin/barracuda-status'
    target.mkdir(parents=True, exist_ok=True)
    shutil.copytree(root / 'barracuda_status', target / 'barracuda_status',
                    dirs_exist_ok=True, ignore=shutil.ignore_patterns('__pycache__', '*.pyc'))
    binary.parent.mkdir(parents=True, exist_ok=True)
    for launcher, module in ((binary, 'app'), (binary.with_name('barracuda-pair'), 'pairing')):
        launcher.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -c ' +
                            shlex.quote('import sys; sys.path.insert(0, ' + repr(str(target)) +
                                        f'); from barracuda_status.{module} import main; '
                                        'raise SystemExit(main())') +
                            ' --language ' + shlex.quote(args.language) + ' "$@"\n')
        launcher.chmod(0o755)
    icon = data / 'icons/hicolor/scalable/apps/barracuda-status.svg'
    icon.parent.mkdir(parents=True, exist_ok=True)
    shutil.copy2(root / 'barracuda_status/assets/barracuda-connected.svg', icon)
    # Desktop Exec is not shell syntax. Quote its reserved characters separately.
    command = str(binary).replace('%', '%%')
    for character in ('\\', '"', '`', '$'):
        command = command.replace(character, '\\' + character)
    desktop = (root / 'packaging/org.razer.BarracudaStatus.desktop').read_text()
    desktop = desktop.replace('Exec=barracuda-status --language en',
                              f'Exec="{command}" --language {args.language}')
    destinations = [data / 'applications']
    if args.autostart:
        destinations.append(config / 'autostart')
    for destination in destinations:
        destination.mkdir(parents=True, exist_ok=True)
        (destination / 'org.razer.BarracudaStatus.desktop').write_text(desktop)
    if args.wireplumber_analog_only:
        rules = config / 'wireplumber/wireplumber.conf.d'
        rules.mkdir(parents=True, exist_ok=True)
        shutil.copy2(root / 'packaging/51-barracuda-analog-only.conf', rules)
        print(f'Installed {rules}/51-barracuda-analog-only.conf; '
              'restart WirePlumber to apply it.')
    print(f'Installed {binary}. Existing processes were not restarted.')


if __name__ == '__main__':
    main()
