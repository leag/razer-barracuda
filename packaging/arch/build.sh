#!/bin/sh -e
# Create the Python sdist from this checkout and build packages from the
# matching GitHub tag configured in PKGBUILD.
cd "$(dirname "$0")/../.."
rm -rf dist
uv build --sdist
cp dist/barracuda_pair-*.tar.gz packaging/arch/
cd packaging/arch
updpkgsums
makepkg -f "$@"
