#!/usr/bin/env bash
# Read the Root of Trust UART reporter output from the Tang Nano 20k.
#
# After programming hw/tro/build/tro.fs, the FPGA streams:
#   TRO UID: <32 hex chars>
#   TRO RND: <8 hex chars>
# once per second at 115200 baud on the onboard USB-UART bridge
# (usually /dev/ttyUSB1 - FT2232 channel B).
#
# Usage: ./hw/tro/test_tangnano20k.sh [serial_device] [seconds]
set -euo pipefail

PORT="${1:-/dev/ttyUSB1}"
SECONDS_TO_READ="${2:-10}"

if [ ! -e "$PORT" ]; then
    echo "error: $PORT not found. Available:" >&2
    ls /dev/ttyUSB* 2>/dev/null || echo "  (none)" >&2
    exit 1
fi

echo "Reading $PORT at 115200 baud for ${SECONDS_TO_READ}s..."
echo "(press the S1 button to reset the FPGA if no output appears)"
echo

stty -F "$PORT" 115200 raw -echo -echoe -echok -crtscts
timeout "$SECONDS_TO_READ" cat "$PORT" || true

echo
echo "Done."
