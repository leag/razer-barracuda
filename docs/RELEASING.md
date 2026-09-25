# Publishing and releases

## Publish the repository

Create an empty repository on GitHub, then add its URL as a remote and push the
local `main` branch:

```bash
git remote add origin <your-repository-url>
git push -u origin main
```

No remote URL is assumed by this project. Review the tracked files with
`git ls-files` before pushing. Do not add ignored files manually.

## Build release artifacts

```bash
uv sync --locked
uv run python -m unittest discover -s tests -v
uv build
```

The wheel contains the runtime package and original SVG icons. The source archive
also contains documentation, installer, packaging templates and tests. Check both
archives for unwanted resources before uploading them. GitHub Actions runs the
unit suite and builds the package; it does not publish releases automatically.

For a ZIP of the tracked source only:

```bash
git archive --format=zip --output=dist/barracuda-status-source.zip HEAD
```

Use tracked source for release archives. For a new release update the version
in `pyproject.toml`, `barracuda_status/__init__.py`, `packaging/arch/PKGBUILD`,
`kernel/hid-razer-barracuda/dkms.conf` and `scripts/install_dkms.py` (the tests
check they agree), then run `uv lock` and commit the updated lockfile.

## Arch packages

`packaging/arch/build.sh` builds `barracuda-status` and
`hid-razer-barracuda-dkms` from an sdist of the tracked tree with `makepkg`.
Check them with `namcap PKGBUILD *.pkg.tar.zst` before publishing.
