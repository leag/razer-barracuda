#!/bin/sh -e
# Build the Arch packages inside a clean archlinux container, as the release
# workflow does. Run from anywhere: docker run -v <checkout>:/src archlinux:base-devel /src/packaging/arch/build-in-container.sh
pacman -Syu --noconfirm --needed git uv python-build python-installer python-setuptools \
  python-wheel python-pyqt6 libpulse dkms hicolor-icon-theme namcap pacman-contrib >/dev/null
useradd -m builder
cp -r /src /home/builder/src
chown -R builder:builder /home/builder/src
su builder -c 'cd ~/src && git config --global --add safe.directory "*" && packaging/arch/build.sh && cd packaging/arch && namcap PKGBUILD *.pkg.tar.zst'
mkdir -p /src/packaging/arch/out
cp /home/builder/src/packaging/arch/*.pkg.tar.zst /home/builder/src/packaging/arch/*.tar.gz /src/packaging/arch/out/
chown -R "$(stat -c %u:%g /src)" /src/packaging/arch/out
