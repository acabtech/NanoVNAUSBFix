#!/usr/bin/env bash
#
# Flash or recover a NanoVNA-H (STM32F072) over SWD with OpenOCD + ST-Link.
#
#   scripts/recover-openocd.sh [options] [firmware.bin]
#
# With no firmware argument the official PCLK recovery image is used. The image
# is written to 0x08000000, verified, and the target is reset. Use this when
# USB/DFU does not enumerate but the SWD pins (PA13/SWDIO, PA14/SWCLK) are
# accessible.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
# shellcheck source=scripts/recovery-lib.sh
source "$ROOT/scripts/recovery-lib.sh"

usage() {
  cat >&2 <<'EOF'
usage: recover-openocd.sh [options] [firmware.bin]

Options:
  --connect-under-reset  Assert NRST while connecting (use if the application
                         has disabled SWD or the MCU is in a low-power state).
  --install-deps         Install openocd, the pinned arm-none-eabi toolchain,
                         and the udev rules.
  --install-udev         Install the NanoVNA + ST-Link udev rules and exit.
  --no-sudo              Run openocd directly instead of through sudo.
  -h, --help             Show this help.

With no firmware.bin, dist/official/NanoVNA-H-1.3.1-omariglol-USB-PCLK.bin is
used. The unofficial image works the same way:
  scripts/recover-openocd.sh dist/unofficial/NanoVNA-H-1.3.1-omariglol.bin
EOF
}

CONNECT_UNDER_RESET=0
USE_SUDO=1
INSTALL_UDEV=0
FILE=""
while (( $# )); do
  case "$1" in
    --connect-under-reset) CONNECT_UNDER_RESET=1 ;;
    --install-deps) RECOVERY_INSTALL_DEPS=1 ;;
    --install-udev) INSTALL_UDEV=1 ;;
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

# Required packages: install the repo package if openocd is missing.
recovery_install_repo_pkg openocd openocd openocd

if (( INSTALL_UDEV )); then
  recovery_install_udev
  exit 0
fi
if (( RECOVERY_INSTALL_DEPS )); then
  recovery_install_udev
fi

OPENOCD_CMD=(
  openocd
  -f interface/stlink.cfg
  -f target/stm32f0x.cfg
  -c "adapter speed 1000"
)
if (( CONNECT_UNDER_RESET )); then
  OPENOCD_CMD+=(-c "reset_config srst_only srst_nogate connect_assert_srst")
fi
OPENOCD_CMD+=(-c "program {$RECOVERY_IMAGE} 0x08000000 verify reset exit")

echo "==> ST-Link/OpenOCD: $RECOVERY_IMAGE (${RECOVERY_IMAGE_SIZE} bytes) -> 0x08000000"
if (( USE_SUDO )); then
  recovery_as_root "${OPENOCD_CMD[@]}"
else
  "${OPENOCD_CMD[@]}"
fi
echo "==> done; set BOOT0 back to GND/low and power-cycle to boot the application"
