#!/usr/bin/env bash
#
# Install udev rules so an unprivileged user can open the NanoVNA USBTMC
# interface with libusb and the ST-Link probe with OpenOCD.
#
#   sudo scripts/install-udev.sh
#
# DEST_DIR can override the rule directory, for packaging or tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
DEST_DIR="${DEST_DIR:-/etc/udev/rules.d}"
RULES=(
  "99-nanovna-usbfix.rules"
  "99-stlink.rules"
)

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: run as root (sudo scripts/install-udev.sh)" >&2
  exit 1
fi

install -d -m 0755 "$DEST_DIR"
for name in "${RULES[@]}"; do
  src="$ROOT/scripts/$name"
  if [[ ! -f "$src" ]]; then
    echo "error: missing rule file: $src" >&2
    exit 1
  fi
  install -m 0644 "$src" "$DEST_DIR/$name"
  echo "installed $DEST_DIR/$name"
done

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add
  echo "reloaded udev rules"
fi

echo "If a device is still inaccessible, unplug and replug it."
echo "On systems using systemd-logind uaccess, log out and back in once."
