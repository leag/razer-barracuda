"""Read-only installation check: reads sysfs, files and process environments only.

It never opens the hidraw node or a driver attribute, so it sends nothing to
the dongle or headset and changes no audio, udev or module state.
"""
import grp
import os
from pathlib import Path
import re
import shutil

from .control import IDENTITY, adapters

MODULE = 'hid_razer_barracuda'
LEGACY_MODULE = 'hid_barracuda'
DRIVER = 'razer-barracuda'
WIDGET = 'org.razer.barracuda.output'
HELPERS = ('barracuda-pair', 'barracuda-power', 'barracuda-headset')
RULES = {
    '99-razer-barracuda.rules': 'pairing access (hidraw)',
    '99-barracuda-battery.rules': 'battery classification',
    '99-barracuda-power.rules': 'power-off and settings access',
}
RULE_DIRS = (Path('/etc/udev/rules.d'), Path('/usr/lib/udev/rules.d'))
QUIRK = 'snd-usb-audio-barracuda'
QUIRK_RETRY = Path('/var/lib/hid-razer-barracuda/quirk-retry')
SPA_ALSA_PLUGINS = ('/usr/lib/spa-0.2/alsa/libspa-alsa.so',
                    '/usr/lib64/spa-0.2/alsa/libspa-alsa.so',
                    '/usr/lib/x86_64-linux-gnu/spa-0.2/alsa/libspa-alsa.so')
OK, WARN, FAIL, INFO = 'ok', 'warn', 'fail', 'info'
MARKS = {OK: '✓', WARN: '!', FAIL: '✗', INFO: '·'}


class Check:
    def __init__(self, status, message, fix=None):
        self.status, self.message, self.fix = status, message, fix


class System:
    """Filesystem roots, replaceable in tests."""
    def __init__(self, root=Path('/'), home=None, release=None, environ=None):
        self.root = Path(root)
        self.home = Path(home) if home else Path.home()
        self.release = release or os.uname().release
        self.environ = os.environ if environ is None else environ

    def path(self, absolute):
        return self.root / Path(absolute).relative_to('/')


def driver_name(device):
    try:
        return (device / 'driver').resolve().name if (device / 'driver').exists() else None
    except OSError:
        return None


def hidraw_nodes(system):
    # The same lookup as barracuda-pair: every hidraw node of the dongle.
    nodes = []
    for node in sorted(system.path('/sys/class/hidraw').glob('hidraw*')):
        try:
            if IDENTITY in (node / 'device/uevent').read_text().splitlines():
                nodes.append(system.path('/dev') / node.name)
        except OSError:
            continue
    return nodes


def check_driver(system):
    checks = []
    if system.path(f'/sys/module/{LEGACY_MODULE}').exists():
        checks.append(Check(FAIL, 'The old hid-barracuda module is loaded and competes for the dongle.',
                            'Remove it as described in docs/DKMS.md, then reboot.'))
    loaded = system.path(f'/sys/module/{MODULE}').exists()
    try:
        devices = adapters(system.path('/sys/bus/hid/devices'))
    except OSError:
        devices = []
    if loaded:
        checks.append(Check(OK, 'The hid-razer-barracuda driver is loaded.'))
    if not devices:
        if not loaded:
            checks.append(Check(WARN, 'The hid-razer-barracuda driver is not loaded.',
                                'Install hid-razer-barracuda-dkms (or scripts/install_dkms.py), then reboot.'))
        checks.append(Check(WARN, 'Dongle not detected; device checks were skipped.',
                            'Plug in the USB dongle and run this check again.'))
        return checks, None, None
    if len(devices) > 1:
        checks.append(Check(WARN, 'More than one Barracuda dongle is connected.',
                            'Keep one dongle connected; the helpers refuse to choose.'))
        return checks, None, None
    device = devices[0]
    bound = driver_name(device)
    if bound == DRIVER:
        checks.append(Check(OK, 'The dongle is bound to the razer-barracuda driver.'))
    elif loaded:
        checks.append(Check(WARN, f'The dongle is bound to {bound or "no driver"}, not razer-barracuda.',
                            'Reconnect the dongle.'))
    else:
        checks.append(Check(FAIL, 'The hid-razer-barracuda driver is not loaded.',
                            'Reboot after installing hid-razer-barracuda-dkms; if it still fails, '
                            'see "dkms status hid-razer-barracuda".'))
    return checks, device, device if bound == DRIVER else None


def check_link(device):
    try:
        reported = (device.resolve().parent / 'wireless_status').read_text().strip()
    except OSError:
        reported = ''
    if reported in ('connected', 'disconnected'):
        return Check(INFO, f'Headset link reported by the driver: {reported}.')
    # Not a fault: the driver publishes a state only after a valid reply.
    return Check(INFO, 'Headset link not confirmed yet; turn the headset on.')


def in_audio_group():
    try:
        audio = grp.getgrnam('audio').gr_gid
    except KeyError:
        return False
    return audio in os.getgroups() or audio == os.getgid()


def check_access(system, device):
    checks = []
    nodes = hidraw_nodes(system)
    if nodes and all(os.access(node, os.R_OK | os.W_OK) for node in nodes):
        checks.append(Check(OK, 'Pairing has access to the dongle.'))
    elif nodes:
        checks.append(Check(FAIL, 'No access to the dongle for pairing.',
                            'Install 99-razer-barracuda.rules, then reconnect the dongle.'))
    if device is not None:
        attributes = [device / name for name in ('headset_settings', 'headset_poweroff')]
        present = [attribute for attribute in attributes if attribute.exists()]
        if not present:
            checks.append(Check(WARN, 'The driver has no settings or power-off controls.',
                                'Update hid-razer-barracuda-dkms and reboot.'))
        elif all(os.access(attribute, os.W_OK) for attribute in present):
            checks.append(Check(OK, 'Headset settings and power-off are available to you.'))
        elif not in_audio_group():
            checks.append(Check(FAIL, 'Headset settings and power-off need the audio group.',
                                'sudo usermod -aG audio "$USER", then log out and back in.'))
        else:
            checks.append(Check(FAIL, 'No access to headset settings and power-off.',
                                'Install 99-barracuda-power.rules, then reconnect the dongle.'))
    return checks


def check_rules(system):
    missing = [name for name in RULES
               if not any(system.path(directory / name).is_file() for directory in RULE_DIRS)]
    if not missing:
        return [Check(OK, 'udev rules are installed.')]
    return [Check(FAIL if name == '99-razer-barracuda.rules' else WARN,
                  f'udev rule {name} ({RULES[name]}) is missing.',
                  'Install the barracuda-pair and hid-razer-barracuda-dkms packages, '
                  'or run scripts/install.py --system from a checkout.')
            for name in missing]


def quirk_built(system):
    for conf in system.path('/usr/src').glob(f'{QUIRK}-*/dkms.conf'):
        try:
            match = re.search(r'^BUILD_EXCLUSIVE_KERNEL="\^(.*)\$"$', conf.read_text(), re.M)
        except OSError:
            continue
        if match and re.sub(r'\\(.)', r'\1', match.group(1)) == system.release:
            return True
    return False


def pipewire_wireless_support(system):
    for plugin in SPA_ALSA_PLUGINS:
        try:
            if b'wireless_status' in system.path(plugin).read_bytes():
                return True
        except OSError:
            continue
    return False


def check_quirk(system):
    # The quirk ships with the driver; without the driver there is nothing to report.
    if not any(system.path('/usr/src').glob('hid-razer-barracuda-*')):
        return []
    if quirk_built(system):
        return [Check(OK, f'The jack quirk is built for kernel {system.release}.')]
    if pipewire_wireless_support(system):
        return [Check(OK, 'PipeWire follows the headset link natively; no jack quirk is needed.')]
    try:
        pending = system.release in system.path(QUIRK_RETRY).read_text().split()
    except OSError:
        pending = False
    if pending:
        return [Check(FAIL, f'The jack quirk build failed for kernel {system.release}.',
                      'sudo barracuda-snd-usb-audio-quirk --all-kernels (needs internet access).')]
    return [Check(WARN, f'No jack quirk for kernel {system.release}; the output stays listed while '
                  'the headset is off.',
                  'Install the headers for this kernel, then run '
                  'sudo barracuda-snd-usb-audio-quirk --all-kernels.')]


def session_path(system):
    """PATH of the running Plasma shell, which is where the widget runs helpers."""
    for proc in system.path('/proc').glob('[0-9]*'):
        try:
            if (proc / 'comm').read_text().strip() != 'plasmashell' or proc.stat().st_uid != os.getuid():
                continue
            for entry in (proc / 'environ').read_bytes().split(b'\0'):
                if entry.startswith(b'PATH='):
                    return entry[5:].decode(errors='replace'), True
        except OSError:
            continue
    return system.environ.get('PATH', ''), False


def check_helpers(system):
    path, from_session = session_path(system)
    where = 'the Plasma session' if from_session else 'this shell (Plasma is not running)'
    missing = [name for name in HELPERS if not shutil.which(name, path=path)]
    if not missing:
        checks = [Check(OK, f'Helpers are on the PATH of {where}.')]
    else:
        local = system.home / '.local/bin'
        fix = (f'Add {local} to your session PATH, then log out and back in.'
               if all((local / name).exists() for name in missing)
               else 'Install the barracuda-pair package, or run scripts/install.py from a checkout.')
        checks = [Check(FAIL, f'Not on the PATH of {where}: {", ".join(missing)}.', fix)]
    user = system.home / '.local/bin/barracuda-pair'
    if user.exists() and system.path('/usr/bin/barracuda-pair').exists():
        checks.append(Check(WARN, 'Both a user copy and the barracuda-pair package are installed.',
                            f'Remove the barracuda-* launchers from {user.parent} and '
                            f'{data_home(system) / "barracuda-pair"}.'))
    return checks


def data_home(system):
    return Path(system.environ.get('XDG_DATA_HOME') or system.home / '.local/share')


def check_widget(system):
    user = (data_home(system) / 'plasma/plasmoids' / WIDGET / 'metadata.json').is_file()
    package = system.path(f'/usr/share/plasma/plasmoids/{WIDGET}/metadata.json').is_file()
    if user and package:
        return [Check(WARN, 'The widget is installed both for your user and by a package.',
                      f'kpackagetool6 --type Plasma/Applet --remove {WIDGET}')]
    if user or package:
        return [Check(OK, 'The Plasma widget is installed.')]
    return [Check(INFO, 'The Plasma widget is not installed.',
                  'Install plasma6-applets-barracuda, or run scripts/install.py --widget.')]


def run_checks(system=None):
    system = system or System()
    checks, adapter, device = check_driver(system)
    if adapter is not None:
        if device is not None:
            checks.append(check_link(device))
        checks.extend(check_access(system, device))
    checks.extend(check_rules(system))
    checks.extend(check_quirk(system))
    checks.extend(check_helpers(system))
    checks.extend(check_widget(system))
    return checks


def report(checks, stream):
    for check in checks:
        print(f'{MARKS[check.status]} {check.message}', file=stream)
        if check.fix and check.status != OK:
            print(f'    {check.fix}', file=stream)
    failed = sum(check.status == FAIL for check in checks)
    warned = sum(check.status == WARN for check in checks)
    if failed or warned:
        print(f'\n{failed} problem(s), {warned} warning(s). Nothing was changed.', file=stream)
    else:
        print('\nEverything is in place. Nothing was changed.', file=stream)
    return 1 if failed else 0
