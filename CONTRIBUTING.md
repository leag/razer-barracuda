# Contributing

Use English for documentation, source comments and source UI strings. Provide a
Spanish entry in `barracuda_pair/i18n.py` for every new CLI message. For widget
text, update the English/Spanish strings in QML and the translated metadata.
The CLI defaults to English regardless of the host locale. The plasmoid follows
the desktop locale, with English fallback; test both English and Spanish.

Keep changes focused. Run:

```bash
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_pair scripts
```

Tests must not change real desktop audio or require hardware. QML tests use an
offscreen platform and mocked sinks. Add coverage for changed protocol or widget behavior.
Read [protocol observations](docs/PROTOCOL.md) before modifying the HID parser.
Do not send unverified commands to the dongle.

Do not commit logs, personal paths, credentials or local settings.
Check `git diff --cached --check` and `git diff --cached` before committing.
The MIT license covers contributions to project code, docs and original assets.
The plasmoid uses installed KDE Breeze artwork via `breeze-icons`; do not copy
those icons into the repository or present them as project-owned assets.

QML logic tests require the Qt 6 test runner. Panel rendering tests additionally
require Plasma components and Breeze icons; check skipped tests before claiming
rendering validation. Run `uv run python -m unittest tests.test_plasmoid -v`
on a Plasma development machine. Tests must not alter live audio.

After changing the driver, installers or packaging files, build the Arch
packages with `packaging/arch/build.sh` and check them with namcap. Before
publishing, inspect the resulting archives. The build script fetches a tag and
does not test uncommitted source changes; see [releasing](docs/RELEASING.md).
After changing the driver, run KUnit in a kernel tree as [UPSTREAM.md](docs/UPSTREAM.md)
describes, and keep the series in `upstream/` in sync with the sources.

Include the problem, resulting behavior and validation in pull requests. Clearly
separate simulated tests from physical-device observations. Test installation in
a temporary HOME/XDG directory before changing a real desktop installation.
