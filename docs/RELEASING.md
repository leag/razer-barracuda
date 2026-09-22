# Publishing and releases

## Publish the repository

Create an empty repository on GitHub, then add its URL as a remote and push the
local `main` branch:

```bash
git remote add origin <your-repository-url>
git push -u origin main
```

No remote URL is assumed by this project. Review the tracked files with
`git ls-files` before pushing. The ignored local `private/`, `.vm/`, environment,
logs and build outputs must not be added manually.

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

Do not archive the entire working directory: it may contain proprietary local
assets and large VM disks even though Git ignores them. Update both version fields
in `pyproject.toml` and `barracuda_status/__init__.py` for a new release, then run
`uv lock` and commit the updated lockfile.
