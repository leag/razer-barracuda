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
archives for unwanted resources before uploading them.

## Releases

A release is the pair of Arch packages. Pushing a tag `vX.Y.Z` that matches
`pkgver` in `packaging/arch/PKGBUILD` runs `.github/workflows/release.yml`,
which builds `barracuda-status` and `hid-razer-barracuda-dkms` in an
`archlinux:base-devel` container with `packaging/arch/build-in-container.sh`,
checks them with namcap, and creates the GitHub release with the two
`.pkg.tar.zst` files and the source archive attached, with generated notes.

```bash
git tag v0.3.3
git push origin v0.3.3
```

To reproduce the release build locally with Docker:

```bash
docker run --rm -v "$PWD":/src archlinux:base-devel /src/packaging/arch/build-in-container.sh
ls packaging/arch/out
```

For a ZIP of the tracked source only:

```bash
git archive --format=zip --output=dist/barracuda-status-source.zip HEAD
```

Use tracked source for release archives. Prepare the next version with one command:

```bash
uv run python scripts/version.py --bump patch
```

Use `--bump minor`, `--bump major` or `--set X.Y.Z` as needed; add `--dry-run`
to preview. `pyproject.toml` is the source of truth. The script delegates the
version change and lockfile update to `uv version --no-sync`, synchronizes the
Python, DKMS and Arch version fields (including `.SRCINFO`), and resets Arch
`pkgrel` to 1 for a new version. Only stable `X.Y.Z` releases are supported.
It does not commit, tag, publish, or update an installed monitor.

If you used `uv version` directly, run `uv run python scripts/version.py --sync`
afterwards. Use `--check` to detect stale distribution metadata. Commit the
version changes and lockfile before creating the matching `vX.Y.Z` tag.

The new tag archive does not exist during the version bump, so its checksum is
refreshed after the tag is pushed. The release build runs `updpkgsums` automatically.
Also run `updpkgsums` and regenerate `.SRCINFO` in `packaging/arch/` afterwards,
then commit those checksum changes to `main` without moving the published tag.

## Arch packages

`packaging/arch/build.sh` creates a Python sdist from the tracked tree for the
GitHub release, then builds `barracuda-status` and `hid-razer-barracuda-dkms`
with `makepkg`. The PKGBUILD fetches the matching GitHub tag archive, so it also
builds from a clean AUR checkout. Regenerate `.SRCINFO` after metadata changes
with `makepkg --printsrcinfo > .SRCINFO` in `packaging/arch/`. Check the packages
with `namcap PKGBUILD *.pkg.tar.zst` before publishing.
