#!/usr/bin/env bash
#
# Fetch and unpack the pinned upstream source without building it. Useful for
# inspecting the tree or developing a new patch.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
VERSION="1.2.50"
URL="https://github.com/hugen79/NanoVNA-H/archive/refs/tags/${VERSION}.tar.gz"
SHA256="3db755b50c84e9c426957882ea9c0c5506febc1310c179a680a1fef9918389ee"
CACHE="$ROOT/build/cache"
OUT="$ROOT/build/upstream"

command -v curl >/dev/null || { echo "missing curl" >&2; exit 1; }
command -v 7z >/dev/null || { echo "missing 7z" >&2; exit 1; }

mkdir -p "$CACHE"
TARBALL="$CACHE/NanoVNA-H-${VERSION}.tar.gz"
if [[ ! -f "$TARBALL" ]]; then
  curl -L --fail --retry 3 -o "$TARBALL.part" "$URL"
  mv "$TARBALL.part" "$TARBALL"
fi
echo "${SHA256}  ${TARBALL}" | sha256sum -c -

rm -rf "$OUT"
mkdir -p "$OUT"
tar xzf "$TARBALL" -C "$OUT" --strip-components=1
if [[ -f "$OUT/ChibiOS.7z" ]]; then
  7z x -y -o"$OUT" "$OUT/ChibiOS.7z" >/dev/null
  rm -f "$OUT/ChibiOS.7z"
fi

echo "upstream source ready in $OUT"
