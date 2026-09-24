#!/bin/sh
# Build mi9t-hardware-support_<version>_arm64.deb (audio DSP + automatic
# rotation) on the phone.
#
#   MI9T_STAGE=<dir> scripts/build/package-hardware.sh
#
# <dir> holds three configured and built meson trees:
#   $MI9T_STAGE/hexagonrpc   https://github.com/linux-msm/hexagonrpc  0.5.0
#   $MI9T_STAGE/libssc       https://github.com/linux-msm/libssc      0.4.4
#   $MI9T_STAGE/iio-proxy    iio-sensor-proxy 3.9 with
#                            hardware-package/patches/iio-startup-race.patch
# each with its build directory at <tree>/build. Optionally
# $MI9T_STAGE/build-tools is put on PYTHONPATH for a newer meson.
#
# Everything else (units, udev rule, WirePlumber rule, UCM profile, sensor
# configuration, DEBIAN/) comes from hardware-package/ in this repository.
# The .deb lands in $MI9T_STAGE.
set -eu
: "${MI9T_STAGE:?set MI9T_STAGE to the directory with the three meson trees}"
stage=$MI9T_STAGE
repo=$(cd "$(dirname "$0")/../.." && pwd)
src=$repo/hardware-package
version=$(sed -n 's/^Version: //p' "$src/DEBIAN/control")
pkg="$stage/hardware-package-$version"
test ! -e "$pkg" || { echo "$pkg exists - remove it first" >&2; exit 1; }
[ -d "$stage/build-tools" ] && export PYTHONPATH="$stage/build-tools"

for source in hexagonrpc libssc iio-proxy; do
  if test "$source" = hexagonrpc; then
    env -u PYTHONPATH meson install -C "$stage/$source/build" --no-rebuild --destdir "$stage/install-$source" > "$stage/install-$source.log"
  else
    python3 -m mesonbuild.mesonmain install -C "$stage/$source/build" --no-rebuild --destdir "$stage/install-$source" > "$stage/install-$source.log"
  fi
done

# Static part of the package, straight from the repository.
mkdir -p "$pkg"
cp -a "$src/DEBIAN" "$src/etc" "$src/usr" "$pkg/"
rm -f "$pkg"/usr/local/bin/* "$pkg"/usr/local/lib/aarch64-linux-gnu/* "$pkg"/usr/local/libexec/*

# Freshly built binaries.
install -m 755 "$stage/install-hexagonrpc/usr/local/bin/hexagonrpcd" "$pkg/usr/local/bin/"
install -m 755 "$stage/install-hexagonrpc/usr/local/lib/aarch64-linux-gnu/libhexagonrpc.so.0.5" "$pkg/usr/local/lib/aarch64-linux-gnu/"
install -m 755 "$stage/install-libssc/usr/local/bin/ssccli" "$pkg/usr/local/bin/"
install -m 755 "$stage/install-libssc/usr/local/lib/aarch64-linux-gnu/libssc.so.2" "$pkg/usr/local/lib/aarch64-linux-gnu/"
install -m 755 "$stage/install-iio-proxy/usr/local/libexec/iio-sensor-proxy" "$pkg/usr/local/libexec/"
install -m 755 "$stage/install-iio-proxy/usr/local/bin/monitor-sensor" "$pkg/usr/local/bin/"
install -m 644 "$stage/install-iio-proxy/usr/local/lib/systemd/system/iio-sensor-proxy.service" "$pkg/usr/local/lib/systemd/system/"
for executable in "$pkg"/usr/local/bin/* "$pkg"/usr/local/libexec/* "$pkg"/usr/local/lib/aarch64-linux-gnu/*; do
  strip --strip-unneeded "$executable"
done
cat "$stage/hexagonrpc/COPYING" "$stage/libssc/LICENSE" "$stage/iio-proxy/COPYING" > "$pkg/usr/share/doc/mi9t-hardware-support/copyright"
chmod 755 "$pkg/DEBIAN/postinst" "$pkg/usr/local/sbin/mi9t-wait-ssc"
find "$pkg/etc" -type f | sed "s|$pkg||" | sort > "$pkg/DEBIAN/conffiles"

dpkg-deb --root-owner-group --build "$pkg" "$stage/mi9t-hardware-support_${version}_arm64.deb"
dpkg-deb --contents "$stage/mi9t-hardware-support_${version}_arm64.deb" | tail -8
