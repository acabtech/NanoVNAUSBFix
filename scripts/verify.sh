#!/usr/bin/env bash
#
# Validate the built artifacts: size, symbols, hashes and required files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
FAIL=0

check_variant() {
  local variant="$1"
  local artifact="$2"
  local dir="$DIST/$variant"
  local bin="$dir/$artifact.bin"
  local hex="$dir/$artifact.hex"
  local elf="$dir/$artifact.elf"

  echo "==> checking $variant"
  for file in "$bin" "$hex" "$elf" "$dir/SHA256SUMS"; do
    if [[ ! -s "$file" ]]; then
      echo "  missing or empty: $file" >&2
      FAIL=1
    fi
  done
  [[ -s "$bin" ]] || return 0

  local size
  size=$(stat -c%s "$bin")
  if (( size > 131072 )); then
    echo "  $bin is ${size} bytes, larger than the 128 KiB flash" >&2
    FAIL=1
  else
    echo "  image size: ${size} bytes"
  fi

  (cd "$dir" && sha256sum -c SHA256SUMS >/dev/null) || {
    echo "  checksum mismatch in $dir/SHA256SUMS" >&2
    FAIL=1
  }
}

check_variant official NanoVNA-H-1.2.50-USB-PCLK
check_variant unofficial NanoVNA-H-1.2.50-USBTMC

unofficial_elf="$DIST/unofficial/NanoVNA-H-1.2.50-USBTMC.elf"
official_elf="$DIST/official/NanoVNA-H-1.2.50-USB-PCLK.elf"

if [[ -s "$unofficial_elf" ]]; then
  for symbol in usbtmc_process usbtmc_configure vna_usb_scpi_exec; do
    if ! arm-none-eabi-nm "$unofficial_elf" | grep -q " $symbol$"; then
      echo "  unofficial ELF is missing symbol $symbol" >&2
      FAIL=1
    fi
  done
fi

if [[ -s "$official_elf" ]] && arm-none-eabi-nm "$official_elf" | grep -q " usbtmc_process$"; then
  echo "  official ELF unexpectedly contains the USBTMC bridge" >&2
  FAIL=1
fi

# Combined checksum manifest for release uploads.
(
  cd "$DIST"
  sha256sum official/NanoVNA-H-1.2.50-USB-PCLK.bin             official/NanoVNA-H-1.2.50-USB-PCLK.hex             official/NanoVNA-H-1.2.50-USB-PCLK.elf             unofficial/NanoVNA-H-1.2.50-USBTMC.bin             unofficial/NanoVNA-H-1.2.50-USBTMC.hex             unofficial/NanoVNA-H-1.2.50-USBTMC.elf > SHA256SUMS
)

if (( FAIL )); then
  echo "verification failed" >&2
  exit 1
fi

echo "all artifacts verified"
