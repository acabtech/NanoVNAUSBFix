#!/usr/bin/env bash
#
# Flash or recover a NanoVNA-H (STM32F072) over the ROM UART bootloader.
#
#   scripts/recover-uart.sh [options] [firmware.bin]
#
# BOOT0 must be high at reset so the ROM bootloader samples USART1:
#   PA9  = USART1_TX  (connect to the USB-UART adapter's RX)
#   PA10 = USART1_RX  (connect to the USB-UART adapter's TX)
# Use 3.3 V TTL levels and a common ground. Requires stm32flash.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/recovery-lib.sh
source "$ROOT/scripts/recovery-lib.sh"

PORT="/dev/ttyUSB0"
BAUD=115200
USE_SUDO=1

usage() {
  cat >&2 <<'EOF'
usage: recover-uart.sh [options] [firmware.bin]

Options:
  -p PORT                Serial device (default: /dev/ttyUSB0).
  -b BAUD                Baud rate (default: 115200).
  --install-deps         Install stm32flash and the pinned arm-none-eabi
                         toolchain.
  --no-sudo              Do not fall back to sudo when the serial device is not
                         accessible to the current user.
  -h, --help             Show this help.

With no firmware.bin, dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.bin is
used. Bootloader wiring is USART1: PA9 (TX) -> adapter RX, PA10 (RX) -> adapter
TX, 3.3 V logic, common GND. BOOT0 must be high at reset.
EOF
}

FILE=""
while (( $# )); do
  case "$1" in
    -p)
      shift
      (( $# )) || { echo "error: -p needs an argument" >&2; exit 2; }
      PORT="$1"
      ;;
    -b)
      shift
      (( $# )) || { echo "error: -b needs an argument" >&2; exit 2; }
      BAUD="$1"
      ;;
    --install-deps) RECOVERY_INSTALL_DEPS=1 ;;
    --no-sudo) USE_SUDO=0 ;;
    -h|--help) usage; exit 0 ;;
    --) shift; break ;;
    -*) echo "error: unknown option: $1" >&2; usage; exit 2 ;;
    *) FILE="$1" ;;
  esac
  shift
done
if (( $# )); then
  [[ -z "$FILE" ]] || { echo "error: only one firmware file may be given" >&2; exit 2; }
  FILE="$1"
fi

recovery_resolve_image "$FILE" official

# --install-deps also guarantees the exact toolchain used for the release
# images, even when a prebuilt image is already present.
if (( RECOVERY_INSTALL_DEPS )); then
  recovery_require_pinned_toolchain
fi

# Required package: stm32flash (AUR on Arch, repo package on Debian).
recovery_install_stm32flash

[[ -c "$PORT" ]] || recovery_die "serial device not found: $PORT"

RUN=(
  stm32flash
  -b "$BAUD"
  -w "$RECOVERY_IMAGE"
  -v
  -g 0x08000000
  "$PORT"
)

echo "==> UART bootloader: $RECOVERY_IMAGE (${RECOVERY_IMAGE_SIZE} bytes) on $PORT at ${BAUD} baud"
if [[ -r "$PORT" && -w "$PORT" ]]; then
  "${RUN[@]}"
elif (( USE_SUDO )); then
  recovery_as_root "${RUN[@]}"
else
  recovery_die "no read/write access to $PORT; add your user to uucp/dialout or rerun without --no-sudo"
fi
echo "==> done; set BOOT0 back to GND/low and power-cycle to boot the application"
