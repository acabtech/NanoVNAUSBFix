#!/usr/bin/env bash
#
# Install a udev rule so an unprivileged user can open the NanoVNA USBTMC
# interface with libusb.
#
#   sudo scripts/install-udev.sh
#
# DEST_DIR can override the rule directory, for packaging or tests.
set -euo pipefail

ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/.." && pwd)"
SRC="$ROOT/scripts/99-nanovna-usbfix.rules"
DEST_DIR="${DEST_DIR:-/etc/udev/rules.d}"
DEST="$DEST_DIR/99-nanovna-usbfix.rules"

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: run as root (sudo scripts/install-udev.sh)" >&2
  exit 1
fi

if [[ ! -f "$SRC" ]]; then
  echo "error: missing rule file: $SRC" >&2
  exit 1
fi

install -d -m 0755 "$DEST_DIR"
install -m 0644 "$SRC" "$DEST"
echo "installed $DEST"

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add
  echo "reloaded udev rules"
fi

echo "If the instrument is still inaccessible, unplug and replug it."
echo "On systems using systemd-logind uaccess, log out and back in once."
