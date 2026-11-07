#!/usr/bin/env bash
#
# Validate the built artifacts: size, symbols, hashes and required files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
FAIL=0

# Flash budgets. The STM32F072 has 128 KiB of flash. Since FLASH-1 the code
# region (flash0) is flavor-specific, because each flavor reserves a different
# amount of storage in flash7:
#
#   official    flash0 114 KiB, flash7 14 KiB  (0x0801C800 + 0x3800)
#   unofficial  flash0 108 KiB, flash7 20 KiB  (0x0801B000 + 0x5000)
#
# The *_FLASH0_LIMIT values are the actual region sizes from each linker script,
# so an image that no longer fits the reservation is caught here. The budgets
# sit below that: official stays frozen at the v0.1.0 baseline (91,704 bytes,
# -O2) despite gaining 18 KiB, and unofficial keeps 2 KiB of margin under its
# new region rather than the old 96 KiB one.
OFFICIAL_MAX=92160             # frozen v0.1.0 baseline; not raised by FLASH-1
UNOFFICIAL_MAX=108544          # -O2 image 100,212 B + 8 KiB margin
OFFICIAL_FLASH0_LIMIT=116736   # flash0 114k
UNOFFICIAL_FLASH0_LIMIT=110592 # flash0 108k

# RAM budgets. Warn when free SRAM drops below 1 KiB and fail below 200 bytes.
# RAM-2/RAM-3 raised the unofficial image from 12 to 316 bytes free, so it now
# clears the floor. CI still sets RAM_ALLOW_LOW=1 for the frozen official image
# and as a one-off bench override; remove that allowance after the next official
# baseline rebuild.
RAM_WARN_FREE=1024
RAM_MIN_FREE=200
RAM_ALLOW_LOW="${RAM_ALLOW_LOW:-0}"

check_variant() {
  local variant="$1"
  local artifact="$2"
  local max_size="$3"
  local flash0_limit="$4"
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
  if (( size > flash0_limit )); then
    echo "  $bin is ${size} bytes, larger than the ${flash0_limit}-byte flash0 region for $variant" >&2
    FAIL=1
  elif (( size > max_size )); then
    echo "  $bin is ${size} bytes, over the ${max_size}-byte budget for $variant" >&2
    FAIL=1
  else
    echo "  image size: ${size} bytes (budget ${max_size}, region ${flash0_limit})"
  fi

  if [[ -s "$elf" ]]; then
    local bss_end ram_end free_ram
    bss_end=$(arm-none-eabi-nm "$elf" | awk '$3 == "_bss_end" { print $1 }')
    ram_end=$(arm-none-eabi-nm "$elf" | awk '$3 == "__ram0_end__" { print $1 }')
    if [[ -n "$bss_end" && -n "$ram_end" ]]; then
      free_ram=$((16#$ram_end - 16#$bss_end))
      if (( free_ram < RAM_MIN_FREE )); then
        if [[ "$RAM_ALLOW_LOW" == "1" ]]; then
          echo "  WARNING: only ${free_ram} bytes of RAM free (floor ${RAM_MIN_FREE}); allowed by RAM_ALLOW_LOW=1" >&2
        else
          echo "  only ${free_ram} bytes of RAM free, below the ${RAM_MIN_FREE}-byte floor" >&2
          FAIL=1
        fi
      elif (( free_ram < RAM_WARN_FREE )); then
        echo "  WARNING: only ${free_ram} bytes of RAM free (target ${RAM_WARN_FREE})" >&2
      else
        echo "  RAM free: ${free_ram} bytes"
      fi
    else
      echo "  could not read _bss_end/__ram0_end__ from $elf" >&2
      FAIL=1
    fi
  fi

  (cd "$dir" && sha256sum -c SHA256SUMS >/dev/null) || {
    echo "  checksum mismatch in $dir/SHA256SUMS" >&2
    FAIL=1
  }
}

check_variant official NanoVNA-H-1.3.1-omariglol-USB-PCLK "$OFFICIAL_MAX" "$OFFICIAL_FLASH0_LIMIT"
check_variant unofficial NanoVNA-H-1.3.1-omariglol "$UNOFFICIAL_MAX" "$UNOFFICIAL_FLASH0_LIMIT"

unofficial_elf="$DIST/unofficial/NanoVNA-H-1.3.1-omariglol.elf"
official_elf="$DIST/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.elf"

# Read the symbol tables once. Piping `nm` directly into `grep -q` is racy under
# `set -o pipefail`: grep exits on the first match, nm dies of SIGPIPE and the
# pipeline reports failure even though the symbol was present.
if [[ -s "$unofficial_elf" ]]; then
  unofficial_syms=$(arm-none-eabi-nm "$unofficial_elf" || true)
  for symbol in usbtmc_process usbtmc_configure vna_usb_scpi_exec \
                vna_usb_data_block; do
    # nm separates the type letter from the name with a tab, not a space.
    if ! grep -qE "[[:space:]]$symbol$" <<< "$unofficial_syms"; then
      echo "  unofficial ELF is missing symbol $symbol" >&2
      FAIL=1
    fi
  done
fi

if [[ -s "$official_elf" ]]; then
  official_syms=$(arm-none-eabi-nm "$official_elf" || true)
  if grep -qE "[[:space:]]usbtmc_process$" <<< "$official_syms"; then
    echo "  official ELF unexpectedly contains the USBTMC bridge" >&2
    FAIL=1
  fi
fi

# Combined checksum manifest for release uploads. Release assets are uploaded
# flat, so list bare filenames rather than the dist/<flavor>/ paths.
(
  cd "$DIST"
  for file in official/*.bin official/*.hex official/*.elf \
              unofficial/*.bin unofficial/*.hex unofficial/*.elf; do
    sha256sum "$file" | sed 's|  .*/|  |'
  done > SHA256SUMS
)

if (( FAIL )); then
  echo "verification failed" >&2
  exit 1
fi

echo "all artifacts verified"
