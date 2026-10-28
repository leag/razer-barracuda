#!/usr/bin/env python3
"""Install the pairing CLI for the current user, without desktop integration.

--system also installs the udev rules, the DKMS driver and the jack quirk with
one pkexec prompt; --widget installs or upgrades the Plasma widget for this
user. Neither reloads modules, restarts audio or changes panel layouts.
"""
import argparse
import os
from pathlib import Path
import shlex
import shutil
import subprocess
import sys

import install_dkms
from install_snd_usb_audio_quirk import pipewire_wireless_support

ROOT = Path(__file__).resolve().parent.parent
MODULES = ('__init__.py', '__main__.py', 'pairing.py', 'control.py', 'headset.py', 'bluetooth.py',
           'doctor.py')
WIDGET = 'org.razer.barracuda.output'
HIDRAW_RULE = '99-razer-barracuda.rules'


def launcher(binary, target, module):
    code = ('import sys; sys.path.insert(0, ' + repr(str(target)) +
            '); from barracuda_pair.' + module + ' import main; raise SystemExit(main())')
    binary.write_text('#!/bin/sh\nexec ' + shlex.quote(sys.executable) + ' -c ' +
                      shlex.quote(code) + ' "$@"\n')
    binary.chmod(0o755)


def driver_installed():
    try:
        status = subprocess.run(['dkms', 'status', '-m', install_dkms.NAME, '-v', install_dkms.VERSION,
                                 '-k', os.uname().release],
                                capture_output=True, text=True, timeout=30).stdout
    except (OSError, subprocess.SubprocessError):
        return False
    return any(line.rstrip().endswith(': installed') for line in status.splitlines())


def system_steps(root=Path('/')):
    """The administrator commands a checkout installation still needs, as argv lists.

    Parts already provided by the Arch packages are left to them.
    """
    python, steps = sys.executable, []
    if not (root / 'usr/lib/udev/rules.d' / HIDRAW_RULE).is_file():
        steps.append(['install', '-Dm644', str(ROOT / 'packaging' / HIDRAW_RULE),
                      f'/etc/udev/rules.d/{HIDRAW_RULE}'])
    if not (root / 'usr/share/hid-razer-barracuda').is_dir():
        # Also installs the battery and power rules and reloads udev rules.
        # DKMS refuses to install the same version twice.
        if not driver_installed():
            steps.append([python, str(ROOT / 'scripts/install_dkms.py')])
        if not pipewire_wireless_support():
            steps.append([python, str(ROOT / 'scripts/install_snd_usb_audio_quirk.py')])
    if steps and steps[0][0] == 'install' and not any('install_dkms.py' in step[-1] for step in steps):
        steps.append(['udevadm', 'control', '--reload-rules'])
    return steps


def install_system(steps):
    if not shutil.which('pkexec'):
        raise SystemExit('pkexec is not available; run these commands with sudo instead:\n' +
                         '\n'.join('  sudo ' + shlex.join(step) for step in steps))
    # One prompt for every step; stop at the first failure.
    script = 'set -e\n' + '\n'.join(shlex.join(step) for step in steps)
    print('Running the administrator steps (password required)…')
    subprocess.run(['pkexec', '/bin/sh', '-c', script], check=True)


def install_widget():
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    if Path('/usr/share/plasma/plasmoids', WIDGET).is_dir():
        print('Skipping the widget: plasma6-applets-barracuda already provides it.')
        return
    action = '--upgrade' if (data / 'plasma/plasmoids' / WIDGET).is_dir() else '--install'
    subprocess.run(['kpackagetool6', '--type', 'Plasma/Applet', action, str(ROOT / 'plasmoid')],
                   check=True, capture_output=True)
    if action == '--upgrade':
        print('Upgraded the widget; log out and back in to load the new version.')
    else:
        print('Installed the widget; the system tray shows it after the next Plasma login.')


def on_path(directory, path):
    return any(Path(entry).expanduser() == directory for entry in path.split(os.pathsep) if entry)


def main():
    parser = argparse.ArgumentParser(description=__doc__,
                                     formatter_class=argparse.RawDescriptionHelpFormatter)
    parser.add_argument('--audio-controls', action='store_true',
                        help='also install the optional barracuda-audio tuning helper; changes no audio settings')
    parser.add_argument('--system', action='store_true',
                        help='also install the udev rules, DKMS driver and jack quirk through pkexec')
    parser.add_argument('--widget', action='store_true',
                        help='also install or upgrade the Plasma widget for this user')
    args = parser.parse_args()
    data = Path(os.environ.get('XDG_DATA_HOME', Path.home() / '.local/share'))
    target = data / 'barracuda-pair'
    package = target / 'barracuda_pair'
    package.mkdir(parents=True, exist_ok=True)
    for name in MODULES:
        shutil.copy2(ROOT / 'barracuda_pair' / name, package / name)
    # Left by installers from before the CLIs became English-only.
    (package / 'i18n.py').unlink(missing_ok=True)
    binary = Path.home() / '.local/bin/barracuda-pair'
    binary.parent.mkdir(parents=True, exist_ok=True)
    launcher(binary, target, 'pairing')
    launcher(binary.with_name('barracuda-power'), target, 'control')
    launcher(binary.with_name('barracuda-headset'), target, 'headset')
    if args.audio_controls:
        shutil.copy2(ROOT / 'barracuda_pair/audio.py', package / 'audio.py')
        (package / 'audio_presets.py').unlink(missing_ok=True)
        license_dir = target / 'LICENSES'
        license_dir.mkdir(exist_ok=True)
        shutil.copy2(ROOT / 'LICENSES/TarikTopalovic-MIT.txt', license_dir)
        launcher(binary.with_name('barracuda-audio'), target, 'audio')
    print(f'Installed barracuda-pair, barracuda-power and barracuda-headset in {binary.parent}.')
    if not on_path(binary.parent, os.environ.get('PATH', '')):
        print(f'{binary.parent} is not on your PATH. Add it to your session environment and log '
              'in again; the widget cannot find the helpers otherwise.')
    steps = system_steps()
    if steps and args.system:
        install_system(steps)
    elif steps:
        print('\nAdministrator steps still needed (--system runs them with one pkexec prompt):')
        for step in steps:
            print('  sudo ' + shlex.join(step))
    if args.widget:
        install_widget()
    print('\nNo desktop entries, autostart, audio settings or loaded modules were changed. '
          'Reboot or reconnect the dongle after installing the driver or rules.')
    sys.path.insert(0, str(target))
    from barracuda_pair import doctor
    print('\nInstallation check:')
    doctor.report(doctor.run_checks(), sys.stdout)


if __name__ == '__main__':
    main()
