#!/bin/sh -e
# Build the Arch packages from the tracked source tree.
cd "$(dirname "$0")/../.."
rm -rf dist
uv build --sdist
cp dist/barracuda_status-*.tar.gz packaging/arch/
cd packaging/arch
updpkgsums
makepkg -f "$@"
