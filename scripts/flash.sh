#!/usr/bin/env bash
#
# Flash one of the built images over DFU. The NanoVNA must already be in DFU
# mode (BOOT0 strapped, or CONFIG -> DFU on a firmware that supports it).
set -euo pipefail

FILE="${1:-}"
if [[ -z "$FILE" || ! -f "$FILE" ]]; then
  echo "usage: $0 <firmware.bin>" >&2
  exit 2
fi

command -v dfu-util >/dev/null || { echo "missing dfu-util" >&2; exit 1; }

echo "==> devices in DFU mode:"
dfu-util -l || true
echo "==> flashing $FILE"
sudo dfu-util -d 0483:df11 -a 0 -s 0x08000000:leave -D "$FILE"
