#!/usr/bin/env bash
#
# Build one NanoVNA-H firmware flavor from the pinned upstream release.
#
#   scripts/build.sh official     PCLK USB-clock fix on stock firmware
#   scripts/build.sh unofficial   PCLK fix + USBTMC/SCPI USB API
#
# The upstream tarball is downloaded once into build/cache, verified against a
# pinned SHA-256, unpacked into build/work/<flavor>, patched, and built.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VARIANT="${1:-official}"
# Project release identity used in artifact filenames. This is independent of
# UPSTREAM_VERSION, which stays pinned to the tarball we patch.
PROJECT_VERSION="1.3.1-omariglol"
UPSTREAM_VERSION="1.2.50"
UPSTREAM_TAG="1.2.50"
UPSTREAM_COMMIT="816495ebc8ca022149787ec2f9e058d6ce3bcb3b"
UPSTREAM_URL="https://github.com/hugen79/NanoVNA-H/archive/refs/tags/${UPSTREAM_TAG}.tar.gz"
UPSTREAM_SHA256="3db755b50c84e9c426957882ea9c0c5506febc1310c179a680a1fef9918389ee"

case "$VARIANT" in
  official)
    PATCHES=(patches/0001-usb-clock-pclk.patch)
    ARTIFACT="NanoVNA-H-${PROJECT_VERSION}-USB-PCLK"
    MAKE_ARGS=(TARGET=F072)
    ;;
  unofficial)
    PATCHES=(
      patches/0001-usb-clock-pclk.patch
      patches/0002-usbtmc-scpi.patch
      patches/0003-usbtmc-shell-output.patch
      patches/0004-scpi-foundation-sweep-parity.patch
      patches/0005-m2-binary-data-transfer.patch
      patches/0006-ram0-stack-command.patch
      patches/0007-ram1-ff-fs-tiny.patch
      patches/0008-fix-spi-buffer-alignment.patch
      patches/0009-ram2-stack-sizes.patch
      patches/0010-ram3-measure-memory.patch
      patches/0011-ram4-trace-index.patch
      patches/0012-ram8-headless.patch
    )
    ARTIFACT="NanoVNA-H-${PROJECT_VERSION}"
    MAKE_ARGS=(TARGET=F072 USBTMC=yes)
    ;;
  *)
    echo "usage: $0 {official|unofficial}" >&2
    exit 2
    ;;
esac

CACHE="$ROOT/build/cache"
WORK="$ROOT/build/work/$VARIANT"
DIST="$ROOT/dist/$VARIANT"
TARBALL="$CACHE/NanoVNA-H-${UPSTREAM_VERSION}.tar.gz"

need() {
  command -v "$1" >/dev/null 2>&1 || {
    echo "error: missing '$1' (see docs/building.md)" >&2
    exit 1
  }
}

need curl
need sha256sum
need tar
need 7z
need patch
need make
need arm-none-eabi-gcc

mkdir -p "$CACHE" "$DIST"

if [[ ! -f "$TARBALL" ]]; then
  echo "==> downloading upstream ${UPSTREAM_TAG} (${UPSTREAM_COMMIT:0:12})"
  curl -L --fail --retry 3 -o "$TARBALL.part" "$UPSTREAM_URL"
  mv "$TARBALL.part" "$TARBALL"
fi

echo "==> verifying upstream tarball"
echo "${UPSTREAM_SHA256}  ${TARBALL}" | sha256sum -c -

echo "==> preparing work tree: $WORK"
rm -rf "$WORK"
mkdir -p "$WORK"
tar xzf "$TARBALL" -C "$WORK" --strip-components=1

# The upstream tarball ships ChibiOS as a 7z archive next to an empty directory.
if [[ -f "$WORK/ChibiOS.7z" ]]; then
  7z x -y -o"$WORK" "$WORK/ChibiOS.7z" >/dev/null
  rm -f "$WORK/ChibiOS.7z"
fi

for patch_file in "${PATCHES[@]}"; do
  echo "==> applying $patch_file"
  patch -d "$WORK" -p1 --forward < "$ROOT/$patch_file"
done

echo "==> building $VARIANT"
make -C "$WORK" clean "${MAKE_ARGS[@]}" >/dev/null
make -C "$WORK" "${MAKE_ARGS[@]}" -j"$(nproc)"

for ext in bin hex elf; do
  cp "$WORK/build/H.$ext" "$DIST/$ARTIFACT.$ext"
done

# Keep the map file for release debugging without cluttering the root.
cp "$WORK/build/H.map" "$DIST/$ARTIFACT.map"

(
  cd "$DIST"
  sha256sum "$ARTIFACT".bin "$ARTIFACT".hex "$ARTIFACT".elf > SHA256SUMS
)

echo
echo "==> $VARIANT firmware written to $DIST"
arm-none-eabi-size "$DIST/$ARTIFACT.elf"
cat "$DIST/SHA256SUMS"
