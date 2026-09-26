# Contributing

Use English for documentation, source comments and source UI strings. Provide a
Spanish entry in `barracuda_status/i18n.py` for every new user-facing message.
English must remain the default regardless of the host locale.

Keep changes focused. Run:

```bash
uv run python -m unittest discover -s tests -v
uv run python -m compileall -q barracuda_status scripts
```

Tests must not change real desktop audio, require hardware or start real tray
workers. Add regression coverage for changed protocol or routing behavior.
Read [protocol observations](docs/PROTOCOL.md) before modifying the HID parser.
Do not send unverified commands to the dongle.

Do not commit logs, personal paths, credentials or local settings.
Check `git diff --cached --check` and `git diff --cached` before committing.
The MIT license covers contributions to project code, docs and original assets.

After changing the driver, installers or packaging files, build the Arch
packages with `packaging/arch/build.sh` and check them with namcap. After
changing the driver, run KUnit in a kernel tree as [UPSTREAM.md](docs/UPSTREAM.md)
describes, and keep the series in `upstream/` in sync with the sources.

Include the problem, resulting behavior and validation in pull requests. Clearly
separate simulated tests from physical-device observations. Test installation in
a temporary HOME/XDG directory before changing a real desktop installation.
