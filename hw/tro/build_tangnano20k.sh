#!/usr/bin/env bash
# Build the Root of Trust bitstream for the Sipeed Tang Nano 20k
# (Gowin GW2AR-18C, QFN88 package).
#
# Toolchain: yosys (synth_gowin) -> nextpnr-himbaechel (gowin) -> gowin_pack
# Requires the shell.nix environment (yosys, nextpnr, apycula, openfpgaloader).
#
# Usage: ./hw/tro/build_tangnano20k.sh
set -euo pipefail

HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
BUILD="$HERE/build"
mkdir -p "$BUILD"

DEVICE="GW2A-LV18QN88C8/I7"   # GW2AR-18C QFN88, speed C8/I7 (Tang Nano 20k)
FAMILY="GW2A-18"
TOP="tangnano20k_top"

# Per-device identity: generated once, then reused so rebuilds keep the same UID.
UID_FILE="$BUILD/uid.hex"
[ -s "$UID_FILE" ] || head -c16 /dev/urandom | od -An -tx1 | tr -d ' \n' > "$UID_FILE"
UID_HEX="$(cat "$UID_FILE")"
echo "Device UID: $UID_HEX"

echo "==> [1/3] Synthesis (yosys synth_gowin)"
yosys -q -p "
  read_verilog -DUID_VAL=128'h$UID_HEX $HERE/root_of_trust.v
  read_verilog $HERE/tangnano20k_top.v
  synth_gowin -top $TOP -json $BUILD/tro.json
"

echo "==> [2/3] Place & route (nextpnr-himbaechel gowin)"
nextpnr-himbaechel \
  --device "$DEVICE" \
  --ignore-loops \
  -o family="$FAMILY" \
  -o cst="$HERE/tangnano20k.cst" \
  --json "$BUILD/tro.json" \
  --write "$BUILD/tro_routed.json" \
  --report "$BUILD/tro_report.json"

echo "==> [3/3] Bitstream (gowin_pack)"
gowin_pack -d "$FAMILY" -o "$BUILD/tro.fs" "$BUILD/tro_routed.json"

echo
echo "Bitstream: $BUILD/tro.fs"
echo "Program:   openFPGALoader -b tangnano20k $BUILD/tro.fs"
