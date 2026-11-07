#!/usr/bin/env bash
#
# Validate the built artifacts: size, symbols, hashes and required files.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DIST="$ROOT/dist"
FAIL=0

# Flash budgets. The STM32F072 has 128 KiB of flash, but the NanoVNA-H linker
# script gives the application only the first 96 KiB (flash0); the last 32 KiB
# (flash7) is reserved for configuration storage. The official image is frozen
# at the v0.1.0 baseline (91,704 bytes, -O2). The unofficial image is built with
# -Os and must keep 2 KiB clear of the code region for safety.
OFFICIAL_MAX=92160
UNOFFICIAL_MAX=96256
FLASH_MAX=98304

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
  if (( size > FLASH_MAX )); then
    echo "  $bin is ${size} bytes, larger than the 128 KiB flash" >&2
    FAIL=1
  elif (( size > max_size )); then
    echo "  $bin is ${size} bytes, over the ${max_size}-byte budget for $variant" >&2
    FAIL=1
  else
    echo "  image size: ${size} bytes (budget ${max_size})"
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

check_variant official NanoVNA-H-1.3.1-omariglol-USB-PCLK "$OFFICIAL_MAX"
check_variant unofficial NanoVNA-H-1.3.1-omariglol "$UNOFFICIAL_MAX"

unofficial_elf="$DIST/unofficial/NanoVNA-H-1.3.1-omariglol.elf"
official_elf="$DIST/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.elf"

if [[ -s "$unofficial_elf" ]]; then
  for symbol in usbtmc_process usbtmc_configure vna_usb_scpi_exec \
                vna_usb_data_block; do
    # nm separates the type letter from the name with a tab, not a space.
    if ! arm-none-eabi-nm "$unofficial_elf" | grep -qE "[[:space:]]$symbol$"; then
      echo "  unofficial ELF is missing symbol $symbol" >&2
      FAIL=1
    fi
  done
fi

if [[ -s "$official_elf" ]] && arm-none-eabi-nm "$official_elf" | grep -qE "[[:space:]]usbtmc_process$"; then
  echo "  official ELF unexpectedly contains the USBTMC bridge" >&2
  FAIL=1
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
