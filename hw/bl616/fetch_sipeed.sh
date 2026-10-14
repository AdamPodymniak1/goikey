#!/usr/bin/env bash
# Download the two Sipeed binaries the GoiKey setup needs (not stored in git: proprietary, unclear redistribution terms)
# and verify their SHA-256. Run from anywhere.
set -euo pipefail
HERE="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
get() { # url file sha256
  [ -s "$2" ] || curl -fsSL -m 120 "$1" -o "$2"
  echo "$3  $2" | sha256sum -c - >/dev/null || { echo "SHA-256 mismatch: $2" >&2; rm -f "$2"; exit 1; }
  echo "ok  $2"
}
# encrypted unconditional bootloader (jumps to 0x20000); distributed in github.com/pepijndevos/bl616_dirtyjtag
get https://raw.githubusercontent.com/pepijndevos/bl616_dirtyjtag/main/bl616_bootloader_0x20000_nano20k_signed.bin \
    "$HERE/goikey/bl616_bootloader_0x20000_nano20k_signed.bin" 1b5d0ed698a3f2bf0b9d4f72d242868da993e737bbea0c8288267b69b73fbc12
# factory Sipeed debugger firmware 2025030317 (restore with recovery/flash_restore_sipeed.ini)
get https://dl.sipeed.com/fileList/TANG/Debugger/onboard/BL616/2025030317/bl616_fpga_partner_20kNano.bin \
    "$HERE/recovery/bl616_fpga_partner_20kNano_2025030317.bin" bc5b1f733a13562c898ff66b540038c116c3d77ca202d0afebd1e7af1c3b3203
