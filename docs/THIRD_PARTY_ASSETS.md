# Third-party assets

The public project uses original generic SVG headset icons. It does not redistribute
Razer logos, Windows utilities, DLLs, firmware, or virtual-machine images.
The MIT license applies to this project's own work, not third-party resources.
Razer and Barracuda are names used to identify supported hardware; this project
is not affiliated with or endorsed by Razer.

Local research files belong in `private/`, which is ignored by Git. Existing VM
storage in `.vm/` is also ignored and must not be deleted during cleanup.
Local extraction provenance and original research notes are kept there as well.
Never use `git add -f` to include these files in a release.

For local use only, the app can optionally read `razer-official.ico` from
`private/razer/` in a source checkout, or from
`$XDG_DATA_HOME/icons/barracuda-status/` (default: `~/.local/share/icons/barracuda-status/`).
The installer does not copy proprietary resources. Public distributions work
without them and use the bundled SVG icons.

Before publishing, inspect `git ls-files` and the contents of built archives.
Ignored files must also be excluded from manually created ZIP archives: use
`git archive` instead of zipping the working directory.
