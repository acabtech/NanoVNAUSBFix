#!/usr/bin/env bash
#
# Capture the read-only USBTMC SCPI baseline for the unofficial firmware.
#
#   scripts/capture-scpi-baseline.sh [usb:0x0483:0x5740]
#
# The script sends only queries and state-preserving commands. It does not
# change sweep settings, calibration, traces or saved configuration. Capture
# the output into docs/testing/v0.1.0-scpi-transcript.txt when the baseline
# changes, then diff it against the previous release.
#
# The :VNA:CMD? escape hatch is excluded by default: in v0.1.0, commands such
# as "info" and "version" wedge the USBTMC stack and later queries time out.
# Set INCLUDE_ESCAPE=1 only on a unit you can power-cycle.
set -euo pipefail

SELECTOR="${1:-usb:0x0483:0x5740}"
RIGLOL="${RIGLOL_BIN:-riglol}"
INCLUDE_ESCAPE="${INCLUDE_ESCAPE:-0}"
BASELINE_LABEL="${BASELINE_LABEL:-v0.1.0}"

if ! command -v "$RIGLOL" >/dev/null 2>&1; then
  echo "error: '$RIGLOL' not found; set RIGLOL_BIN or install omariglol" >&2
  exit 1
fi

echo "# $BASELINE_LABEL SCPI baseline"
echo "# selector: $SELECTOR"
echo "# date: $(date -u +%Y-%m-%dT%H:%M:%SZ)"
echo "# kernel: $(uname -srm)"
echo

commands=(
  "*IDN?"
  "*OPC?"
  ":SYST:ERR?"
  ":VNA:SWE:START?"
  ":VNA:SWE:STOP?"
  ":VNA:SWE:POINTS?"
  ":VNA:FREQ?"
  ":VNA:DATA:CHUNK? 0,0,3"
  ":VNA:DATA:CHUNK? 1,0,3"
)

if [[ "$INCLUDE_ESCAPE" == "1" ]]; then
  commands+=(":VNA:CMD? info" ":VNA:CMD? version")
fi

for command in "${commands[@]}"; do
  echo "\$ $command"
  if ! timeout 20 "$RIGLOL" scpi --usb "$SELECTOR" "$command" 2>&1; then
    echo "[command failed]"
  fi
  echo
done
