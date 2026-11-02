#!/usr/bin/env bash
#
# Remove the NanoVNA USBFix udev rule installed by scripts/install-udev.sh.
#
#   sudo scripts/uninstall-udev.sh
#
# DEST_DIR can override the rule directory, for packaging or tests.
set -euo pipefail

DEST_DIR="${DEST_DIR:-/etc/udev/rules.d}"
DEST="$DEST_DIR/99-nanovna-usbfix.rules"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: run as root (sudo scripts/uninstall-udev.sh)" >&2
  exit 1
fi

if [[ -e "$DEST" ]]; then
  rm -f "$DEST"
  echo "removed $DEST"
else
  echo "not installed: $DEST"
fi

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add
  echo "reloaded udev rules"
fi
