# Publishing and releases

## Publish the repository

Create an empty repository on GitHub, then add its URL as a remote and push the
local `main` branch:

```bash
git remote add origin <your-repository-url>
git push -u origin main
```

The distribution metadata points to `leag/razer-barracuda`; forks must update
those URLs before publishing their own packages. Review the tracked files with
`git ls-files` before pushing. Do not add ignored files manually.

## Build release artifacts

```bash
uv sync --locked
uv run python -m unittest discover -s tests -v
uv build
```

The wheel contains only the pairing runtime package, without Qt or tray assets. The source archive
also contains documentation, installer, packaging templates and tests. Check both
archives for unwanted resources before uploading them. The wheel uses the
`barracuda_pair` module; the sdist also carries the QML widget and its tests.
KDE Breeze artwork is an external runtime dependency, not a bundled asset.

## Releases

A release contains three Arch packages. Pushing a tag `vX.Y.Z` that matches
`pkgver` in `packaging/arch/PKGBUILD` runs `.github/workflows/release.yml`,
which builds `barracuda-pair`, `hid-razer-barracuda-dkms` and
`plasma6-applets-barracuda` in an
`archlinux:base-devel` container with `packaging/arch/build-in-container.sh`,
checks them with namcap, and creates the GitHub release with the three
`.pkg.tar.zst` files and the source archive attached, with generated notes.

```bash
# After bumping, testing and committing the new version:
git tag -a vX.Y.Z -m "Barracuda Linux X.Y.Z"
git push --atomic origin main vX.Y.Z
```

To reproduce the release build locally with Docker:

```bash
docker run --rm -v "$PWD":/src archlinux:base-devel /src/packaging/arch/build-in-container.sh
ls packaging/arch/out
```

For a ZIP of the tracked source only:

```bash
git archive --format=zip --output=dist/barracuda-linux-source.zip HEAD
```

Use tracked source for release archives. Prepare the next version with one command:

```bash
uv run python scripts/version.py --bump patch
```

Use `--bump minor`, `--bump major` or `--set X.Y.Z` as needed; add `--dry-run`
to preview. `pyproject.toml` is the source of truth. The script delegates the
version change and lockfile update to `uv version --no-sync`, synchronizes the
Python, plasmoid, DKMS and Arch version fields (including `.SRCINFO`), and resets Arch
`pkgrel` to 1 for a new version. Only stable `X.Y.Z` releases are supported.
It does not commit, tag, publish, or update installed packages.

If you used `uv version` directly, run `uv run python scripts/version.py --sync`
afterwards. Use `--check` to detect stale distribution metadata. Commit the
version changes and lockfile before creating the matching `vX.Y.Z` tag.

The new tag archive does not exist during the version bump, so its checksum is
refreshed after the tag is pushed. The release build runs `updpkgsums` automatically.
Also run `updpkgsums` and regenerate `.SRCINFO` in `packaging/arch/` afterwards,
then commit those checksum changes to `main` without moving the published tag.

## Arch packages

`packaging/arch/build.sh` creates a Python sdist from the tracked tree for the
GitHub release, then builds the three packages
with `makepkg`. The PKGBUILD fetches the matching GitHub tag archive, so it also
builds from a clean AUR checkout. Regenerate `.SRCINFO` after metadata changes
with `makepkg --printsrcinfo > .SRCINFO` in `packaging/arch/`. Check the packages
with `namcap PKGBUILD *.pkg.tar.zst` before publishing.

Changing `pkgrel` alone does not publish new source: PKGBUILD still fetches the
existing `v$pkgver` tag. For source changes such as the module rename or headset
icon, bump the project version and publish a new tag. Do not move an existing
release tag. Locally built `0.4.0-6` packages do not imply a GitHub release.
The release/checksum follow-up does not update installed copies or restart Plasma.
