#!/usr/bin/env bash
#
# Install the exact arm-none-eabi toolchain used to measure the flash budgets.
#
# The size checks in scripts/verify.sh are only meaningful when CI links the
# firmware with the same compiler as the documented baseline. Ubuntu 24.04's
# gcc-arm-none-eabi 13.2.1 produces a 94,208-byte official image (over budget)
# while the Arch-packaged 16.2.0 toolchain produces the 91,704-byte baseline.
#
# This script runs inside an archlinux:base-devel container on the CI runner.
# The cross-toolchain packages are pinned by exact filename, URL and SHA-256;
# the package files are cached in build/pacman-cache between runs so a cache
# hit performs no network download at all.
#
# The primary mirror keeps only the current package version. The Arch Linux
# Archive keeps every version, so it is the fallback when a pinned file has
# been dropped from the mirror. Bump the versions here (and the actions/cache
# key in .github/actions/setup-toolchain/action.yml) together.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# Keep the cache inside the workspace so actions/cache can persist it.
PKG_CACHE="${PKG_CACHE:-$ROOT/build/pacman-cache}"
MIRROR="https://geo.mirror.pkgbuild.com"
ALA="https://archive.archlinux.org/packages"

EXPECTED_GCC="16.2.0"

# "<mirror path>|<archive path>|<sha256>"
PACKAGES=(
  "extra/os/x86_64/arm-none-eabi-binutils-2.47-1-x86_64.pkg.tar.zst|a/arm-none-eabi-binutils/arm-none-eabi-binutils-2.47-1-x86_64.pkg.tar.zst|b494d4e01cc35c4bcef8522c28d32a9b086460f1037eaaa7a046f2c378d0d7d1"
  "extra/os/x86_64/arm-none-eabi-newlib-4.6.0.20260123-1-any.pkg.tar.zst|a/arm-none-eabi-newlib/arm-none-eabi-newlib-4.6.0.20260123-1-any.pkg.tar.zst|52a414b03ef9a641b0d1e2009e093998954cbe95196cfac7649e47f97e23eda3"
  "extra/os/x86_64/arm-none-eabi-gcc-16.2.0-1-x86_64.pkg.tar.zst|a/arm-none-eabi-gcc/arm-none-eabi-gcc-16.2.0-1-x86_64.pkg.tar.zst|b3fca2319f030bafe17873b4cbcaef3d643043a99f18317cc2793bcaf563b702"
)

echo "==> installing host packages for the build"
pacman -Syu --noconfirm --needed curl 7zip

mkdir -p "$PKG_CACHE"
files=()
for entry in "${PACKAGES[@]}"; do
  IFS='|' read -r mirror_path archive_path sha <<<"$entry"
  name="${mirror_path##*/}"
  file="$PKG_CACHE/$name"

  if [[ -s "$file" ]]; then
    echo "==> using cached $name"
  else
    echo "==> downloading $name"
    downloaded=0
    for base in "$MIRROR" "$ALA"; do
      if [[ "$base" == "$MIRROR" ]]; then
        url="$MIRROR/$mirror_path"
      else
        url="$ALA/$archive_path"
      fi
      if curl -fL --retry 3 --retry-delay 2 --connect-timeout 20 -o "$file.part" "$url"; then
        mv "$file.part" "$file"
        downloaded=1
        break
      fi
      rm -f "$file.part"
      echo "    $url unavailable, trying next source"
    done
    if (( ! downloaded )); then
      echo "error: could not download $name" >&2
      exit 1
    fi
  fi

  echo "$sha  $file" | sha256sum -c -
  files+=("$file")
done

echo "==> installing pinned arm-none-eabi toolchain"
pacman -U --noconfirm "${files[@]}"

actual="$(arm-none-eabi-gcc -dumpversion)"
if [[ "$actual" != "$EXPECTED_GCC" ]]; then
  echo "error: expected arm-none-eabi-gcc $EXPECTED_GCC, got $actual" >&2
  exit 1
fi
arm-none-eabi-gcc --version | head -1
arm-none-eabi-ld --version | head -1
