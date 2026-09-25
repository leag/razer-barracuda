#!/usr/bin/env python3
"""Install snd-usb-audio with the Barracuda X jack quirk as a DKMS module for one kernel.

Downloads sound/usb for the running kernel's upstream stable version, applies
kernel/snd-usb-audio/*.patch only if it applies cleanly, and installs a DKMS
package restricted to that exact kernel release. Other kernels keep the
official module without jack detection.
The downloaded sound/usb sources are GPL-2.0 and are not stored in this repository.
"""
import argparse
import os
from pathlib import Path
import re
import shutil
import subprocess
import tempfile

NAME = 'snd-usb-audio-barracuda'
REVISION = 'barracuda1'
STABLE = 'https://github.com/gregkh/linux.git'
ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'kernel' / 'snd-usb-audio'


def run(*command, cwd=None):
    subprocess.run(command, check=True, timeout=900, cwd=cwd)


def upstream_version(release):
    """7.2.6-1-cachyos -> v7.2.6; 7.3-rc1 is rejected; 7.3.0 is the v7.3 tag."""
    match = re.match(r'^(\d+)\.(\d+)(?:\.(\d+))?(?:[-+].*)?$', release)
    # Release candidates have no stable tag to fetch.
    if not match or re.search(r'-rc\d', release):
        raise ValueError(f'Unsupported kernel release: {release}')
    major, minor, patch = match.groups()
    if patch in (None, '0'):
        return f'v{major}.{minor}'
    return f'v{major}.{minor}.{patch}'


def package_version(release):
    return upstream_version(release)[1:] + '-' + REVISION


def dkms_conf(release):
    return (f'PACKAGE_NAME="{NAME}"\n'
            f'PACKAGE_VERSION="{package_version(release)}"\n'
            'BUILT_MODULE_NAME[0]="snd-usb-audio"\n'
            'BUILT_MODULE_LOCATION[0]="sound/usb/"\n'
            'DEST_MODULE_LOCATION[0]="/updates/dkms"\n'
            # The sources match this kernel only; other kernels keep the official module.
            f'BUILD_EXCLUSIVE_KERNEL="^{re.escape(release)}$"\n'
            'AUTOINSTALL="yes"\n'
            'MAKE[0]="make KDIR=/lib/modules/${kernelver}/build"\n')


def patches():
    found = sorted(SOURCE.glob('*.patch'))
    if not found:
        raise RuntimeError(f'No patch found in {SOURCE}')
    return found


def fetch_sound_usb(tag, work):
    run('git', 'clone', '-q', '--depth', '1', '--filter=blob:none', '--sparse',
        '-b', tag, STABLE, str(work))
    run('git', 'sparse-checkout', 'set', 'sound/usb', cwd=work)


def apply_patches(tree):
    for patch in patches():
        # Refuse to build anything unless every patch applies cleanly.
        run('git', 'apply', '--check', str(patch), cwd=tree)
        run('git', 'apply', str(patch), cwd=tree)


def stage(tree, release, target):
    if target.is_symlink():
        raise RuntimeError(f'Refusing symlink destination: {target}')
    if target.exists():
        raise RuntimeError(f'{target} exists. Remove it with --remove before reinstalling.')
    target.mkdir(mode=0o755)
    shutil.copytree(tree / 'sound' / 'usb', target / 'sound' / 'usb')
    shutil.copyfile(SOURCE / 'Makefile', target / 'Makefile')
    for patch in patches():
        shutil.copyfile(patch, target / patch.name)
    (target / 'dkms.conf').write_text(dkms_conf(release))


def main():
    parser = argparse.ArgumentParser(prog='install_snd_usb_audio_quirk.py', description=__doc__)
    parser.add_argument('--kernel', default=os.uname().release,
                        help='kernel release to build for (default: running kernel)')
    parser.add_argument('--remove', action='store_true',
                        help='remove this DKMS package for the kernel')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run this installer with sudo or pkexec; it writes /usr/src and installs a kernel module')
    if not shutil.which('dkms') or not shutil.which('git'):
        parser.error('Install dkms, git and the headers for your kernel first')
    version = package_version(args.kernel)
    target = Path('/usr/src') / f'{NAME}-{version}'
    if args.remove:
        run('dkms', 'remove', '-m', NAME, '-v', version, '--all')
        shutil.rmtree(target, ignore_errors=True)
        print(f'Removed {NAME} {version}. Reboot or reload snd-usb-audio to use the official module.')
        return
    with tempfile.TemporaryDirectory(prefix='snd-usb-audio-') as directory:
        tree = Path(directory) / 'linux'
        fetch_sound_usb(upstream_version(args.kernel), tree)
        apply_patches(tree)
        stage(tree, args.kernel, target)
    run('dkms', 'install', '-m', NAME, '-v', version, '-k', args.kernel)
    print(f'Installed {NAME} {version} for {args.kernel}. It loads on the next boot or when '
          'snd-usb-audio is reloaded with audio stopped. No audio services were restarted.')


if __name__ == '__main__':
    main()
