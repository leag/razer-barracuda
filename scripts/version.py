#!/usr/bin/env python3
"""Use uv to update the project version and synchronize distribution metadata."""
import argparse
import json
from pathlib import Path
import re
import subprocess

ROOT = Path(__file__).resolve().parents[1]
FIELDS = {
    'plasmoid/metadata.json': (r'^        "Version": "[^"]+",$',
                              '        "Version": "{version}",'),
    'barracuda_status/__init__.py': (r'^__version__ = "[^"]+"$', '__version__ = "{version}"'),
    'scripts/install_dkms.py': (r"^VERSION = '[^']+'$", "VERSION = '{version}'"),
    'kernel/hid-razer-barracuda/dkms.conf':
        (r'^PACKAGE_VERSION="[^"]+"$', 'PACKAGE_VERSION="{version}"'),
    'packaging/arch/PKGBUILD': (r'^pkgver=\S+$', 'pkgver={version}'),
    'packaging/arch/.SRCINFO': (r'^\tpkgver = \S+$', '\tpkgver = {version}'),
}


def replace_once(text, pattern, replacement, path):
    result, count = re.subn(pattern, lambda match: replacement, text, flags=re.M)
    if count != 1:
        raise ValueError(f'Expected exactly one version field matching {pattern!r} in {path}')
    return result


def planned_updates(root, version):
    if not re.fullmatch(r'(0|[1-9]\d*)\.(0|[1-9]\d*)\.(0|[1-9]\d*)', version):
        raise ValueError('Arch/DKMS releases require a stable major.minor.patch version')
    updates = {}
    for name, (pattern, template) in FIELDS.items():
        path = root / name
        original = path.read_text()
        updated = replace_once(original, pattern, template.format(version=version), path)
        if name == 'packaging/arch/PKGBUILD' and updated != original:
            updated = replace_once(updated, r'^pkgrel=\S+$', 'pkgrel=1', path)
        if name == 'packaging/arch/.SRCINFO':
            if updated != original:
                updated = replace_once(updated, r'^\tpkgrel = \S+$', '\tpkgrel = 1', path)
            updated = replace_once(
                updated, r'^\tsource = razer-barracuda-.*$',
                f'\tsource = razer-barracuda-{version}.tar.gz::'
                f'https://github.com/leag/razer-barracuda/archive/refs/tags/v{version}.tar.gz', path)
        if updated != original:
            updates[path] = updated
    return updates


def main(argv=None, root=ROOT):
    parser = argparse.ArgumentParser(description=__doc__)
    action = parser.add_mutually_exclusive_group(required=True)
    action.add_argument('--bump', choices=('major', 'minor', 'patch'))
    action.add_argument('--set', dest='version', metavar='VERSION')
    action.add_argument('--sync', action='store_true', help='sync from the current pyproject.toml')
    action.add_argument('--check', action='store_true', help='check metadata without writing')
    parser.add_argument('--dry-run', action='store_true')
    args = parser.parse_args(argv)
    change = ['--bump', args.bump] if args.bump else [args.version] if args.version else []
    command = ['uv', 'version', '--no-sync', '--output-format', 'json', *change]
    preview = subprocess.run([*command, '--dry-run'], cwd=root, check=True,
                             capture_output=True, text=True, timeout=120)
    version = json.loads(preview.stdout)['version']
    updates = planned_updates(root, version)
    if args.check:
        for path in updates:
            print(f'Out of sync: {path.relative_to(root)} (expected {version})')
        return int(bool(updates))
    print(f'Project version: {version}')
    for path in updates:
        print(f'Update {path.relative_to(root)}')
    if args.dry_run:
        return 0
    # Preflight every metadata field before allowing uv to modify the project.
    snapshots = {root / name: (root / name).read_bytes() if (root / name).exists() else None
                 for name in ('pyproject.toml', 'uv.lock')}
    snapshots.update({path: path.read_bytes() for path in updates})
    try:
        subprocess.run(command, cwd=root, check=True, timeout=120)
        if args.sync:
            subprocess.run(['uv', 'lock'], cwd=root, check=True, timeout=120)
        for path, content in updates.items():
            path.write_text(content)
    except (OSError, subprocess.SubprocessError):
        for path, content in snapshots.items():
            if content is None:
                path.unlink(missing_ok=True)
            else:
                path.write_bytes(content)
        raise
    if change:
        print('After publishing the tag, refresh the Arch source checksum with updpkgsums '
              'and regenerate .SRCINFO. The release build does this checksum step automatically.')
    return 0


if __name__ == '__main__':
    raise SystemExit(main())
