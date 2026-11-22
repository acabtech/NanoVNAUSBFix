#!/usr/bin/env bash
#
# Remove the udev rules installed by scripts/install-udev.sh.
#
#   sudo scripts/uninstall-udev.sh
#
# DEST_DIR can override the rule directory, for packaging or tests.
set -euo pipefail

DEST_DIR="${DEST_DIR:-/etc/udev/rules.d}"
RULES=(
  "99-nanovna-usbfix.rules"
  "99-stlink.rules"
)

if [[ "$(id -u)" -ne 0 ]]; then
  echo "error: run as root (sudo scripts/uninstall-udev.sh)" >&2
  exit 1
fi

for name in "${RULES[@]}"; do
  dest="$DEST_DIR/$name"
  if [[ -e "$dest" ]]; then
    rm -f "$dest"
    echo "removed $dest"
  else
    echo "not installed: $dest"
  fi
done

if command -v udevadm >/dev/null 2>&1; then
  udevadm control --reload-rules
  udevadm trigger --subsystem-match=usb --action=add
  echo "reloaded udev rules"
fi
