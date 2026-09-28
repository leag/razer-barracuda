#!/usr/bin/env python3
"""Install snd-usb-audio with the Barracuda X jack quirk as a DKMS module for one kernel.

Downloads sound/usb for the running kernel's upstream stable version, applies
kernel/snd-usb-audio/*.patch only if it applies cleanly, and installs a DKMS
package restricted to that exact kernel release. Other kernels keep the
official module without jack detection.
Also installs an ALSA card profile set for the dongle, selected by a udev
rule, so that the microphone follows the headset link like the output does
and the S/PDIF and AC3 profiles are not offered.
The downloaded sound/usb sources are GPL-2.0 and are not stored in this repository.
"""
import argparse
import hashlib
import os
from pathlib import Path
import re
import shutil
import subprocess
import sys
import tempfile

NAME = 'snd-usb-audio-barracuda'
REVISION = 'barracuda1'
STABLE = 'https://github.com/gregkh/linux.git'
ROOT = Path(__file__).resolve().parent.parent
SOURCE = ROOT / 'kernel' / 'snd-usb-audio'
PACKAGING = ROOT / 'packaging'
ACP = Path('usr/share/alsa-card-profile/mixer')
SPA_ALSA_PLUGINS = ('/usr/lib/spa-0.2/alsa/libspa-alsa.so',
                    '/usr/lib64/spa-0.2/alsa/libspa-alsa.so',
                    '/usr/lib/x86_64-linux-gnu/spa-0.2/alsa/libspa-alsa.so')
PROFILE_FILES = {
    'razer-barracuda.conf': ACP / 'profile-sets',
    'analog-input-headset-mic-razer-barracuda.conf': ACP / 'paths',
    '89-razer-barracuda-acp.rules': Path('etc/udev/rules.d'),
    '51-barracuda-headphones.conf': Path('usr/share/wireplumber/wireplumber.conf.d'),
}


def run(*command, cwd=None):
    subprocess.run(command, check=True, timeout=900, cwd=cwd)


def pipewire_wireless_support(paths=SPA_ALSA_PLUGINS):
    """Detect the ALSA feature, including distribution backports.

    This checks the installed plugin, not the user's audio session or the
    dongle's current link.
    """
    for path in paths:
        try:
            if b'wireless_status' in Path(path).read_bytes():
                return True
        except OSError:
            continue
    return False


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
    # Different distribution kernels can share an upstream version.
    identity = hashlib.sha256(release.encode()).hexdigest()[:16]
    return upstream_version(release)[1:] + '-' + REVISION + '-' + identity


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


def profile_targets(root=Path('/')):
    return {PACKAGING / name: root / directory / name
            for name, directory in PROFILE_FILES.items()}


def install_profile_set(root=Path('/')):
    """Copy the profile set, its path and the udev rule that selects it."""
    for source, target in profile_targets(root).items():
        if target.is_symlink():
            raise RuntimeError(f'Refusing symlink destination: {target}')
        target.parent.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(source, target)
        target.chmod(0o644)


def remove_profile_set(root=Path('/')):
    for target in profile_targets(root).values():
        if target.is_file() and not target.is_symlink():
            target.unlink()


def dkms_status(version, release=None):
    command = ['dkms', 'status', '-m', NAME, '-v', version]
    if release:
        command.extend(['-k', release])
    return subprocess.run(command, check=True, timeout=30,
                          capture_output=True, text=True).stdout.strip()


def install_kernel(release, source_root=Path('/usr/src'), managed=False):
    version = package_version(release)
    target = source_root / f'{NAME}-{version}'
    if target.is_symlink():
        raise RuntimeError(f'Refusing symlink destination: {target}')
    if target.exists():
        if (target / 'dkms.conf').read_text() != dkms_conf(release):
            raise RuntimeError(f'Unexpected DKMS configuration in {target}')
    else:
        with tempfile.TemporaryDirectory(prefix='snd-usb-audio-') as directory:
            tree = Path(directory) / 'linux'
            fetch_sound_usb(upstream_version(release), tree)
            apply_patches(tree)
            stage(tree, release, target)
    if managed:
        (target / '.pacman-managed').touch()
    # Retrying after a failed build reuses only successfully patched sources.
    if not any(line.endswith(': installed') for line in dkms_status(version, release).splitlines()):
        run('dkms', 'install', '-m', NAME, '-v', version, '-k', release)


def all_kernels(modules=Path('/usr/lib/modules'), source_root=Path('/usr/src'),
                remove=False, force=False):
    failures = []
    if remove:
        targets = sorted(source_root.glob(f'{NAME}-*/.pacman-managed'))
        for marker in targets:
            target = marker.parent
            if target.is_symlink() or marker.is_symlink():
                raise RuntimeError(f'Refusing symlink destination: {target}')
            version = target.name[len(NAME) + 1:]
            if dkms_status(version):
                run('dkms', 'remove', '-m', NAME, '-v', version, '--all')
            shutil.rmtree(target)
        return 0
    if not force and pipewire_wireless_support():
        print('PipeWire ALSA supports USB wireless_status; skipping the jack quirk. '
              'Existing quirk builds are kept. Use --all-kernels --remove to remove '
              'package-managed builds after verifying native switching, then reboot.')
        return 0
    releases = sorted(path.parent.parent.name for path in modules.glob('*/build/Makefile'))
    if not releases:
        print('No kernel headers found; install the headers package to build the Barracuda jack quirk.')
    for release in releases:
        try:
            install_kernel(release, source_root, managed=True)
        except (OSError, ValueError, RuntimeError, subprocess.SubprocessError) as error:
            failures.append(release)
            print(f'Barracuda jack quirk failed for {release}: {error}. '
                  'Retry with sudo barracuda-snd-usb-audio-quirk --all-kernels.', file=sys.stderr)
    if releases:
        print('Reboot to load newly installed modules. No audio services were restarted.')
    return int(bool(failures))


def main():
    parser = argparse.ArgumentParser(prog='install_snd_usb_audio_quirk.py', description=__doc__)
    kernels = parser.add_mutually_exclusive_group()
    kernels.add_argument('--kernel', default=os.uname().release,
                        help='kernel release to build for (default: running kernel)')
    kernels.add_argument('--all-kernels', action='store_true',
                         help='install for all kernels with headers; with --remove, remove package-managed builds')
    parser.add_argument('--remove', action='store_true',
                        help='remove this DKMS package for the kernel')
    parser.add_argument('--no-profile-set', action='store_true',
                        help='leave the ALSA card profile set alone (installed by a package)')
    parser.add_argument('--force', action='store_true',
                        help='with --all-kernels, install even if PipeWire supports wireless_status')
    args = parser.parse_args()
    if os.geteuid() != 0:
        parser.error('Run this installer with sudo or pkexec; it writes /usr/src and installs a kernel module')
    if not shutil.which('dkms') or not shutil.which('git'):
        parser.error('Install dkms, git and the headers for your kernel first')
    if args.all_kernels:
        return all_kernels(remove=args.remove, force=args.force)
    version = package_version(args.kernel)
    target = Path('/usr/src') / f'{NAME}-{version}'
    if args.remove:
        run('dkms', 'remove', '-m', NAME, '-v', version, '--all')
        shutil.rmtree(target, ignore_errors=True)
        if not args.no_profile_set:
            remove_profile_set()
        print(f'Removed {NAME} {version}. Reboot or reload snd-usb-audio to use the official module.')
        return
    install_kernel(args.kernel)
    if not args.no_profile_set:
        install_profile_set()
    print(f'Installed {NAME} {version} for {args.kernel}. It loads on the next boot or when '
          'snd-usb-audio is reloaded with audio stopped. No audio services were restarted.\n'
          'The Barracuda ALSA card profile set applies after a reboot, or after '
          '"udevadm trigger --subsystem-match=sound" and a WirePlumber restart.')


if __name__ == '__main__':
    sys.exit(main())
