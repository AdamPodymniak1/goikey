{ pkgs ? import <nixpkgs> {} }:

pkgs.mkShell {
  packages = with pkgs; [
    platformio
    yosys
    nextpnr
    openfpgaloader
    python3Packages.apycula
    iverilog
    (python3.withPackages (p: [ p.cryptography p.pyserial ]))
  ];

  shellHook = ''
    export PLATFORMIO_CORE_DIR="$PWD/.platformio-core"
    echo "ESP32 tools: platformio (pio)"
    echo "FPGA tools:  yosys, nextpnr-himbaechel (gowin), gowin_pack, openFPGALoader"
    echo ""
    echo "Build ESP32:   pio run -e esp32s3"
    echo "Flash ESP32:   pio run -e esp32s3 -t upload -t monitor"
    echo ""
    echo "Build FPGA crypto accelerator (Tang Nano 20k, GW2AR-18C):"
    echo "  ./hw/accel/build_accel.sh main     # or sym (SHA-256/HMAC/PBKDF2/AES)"
    echo "Program FPGA (SRAM; -f writes flash):"
    echo "  openFPGALoader -b tangnano20k hw/accel/build/accel_main.fs"
    echo ""
    if ! id -nG | grep -qw dialout; then
      echo "NOTE: your user is not in the 'dialout' group - USB serial uploads"
      echo "      will fail until you add users.users.<you>.extraGroups = [ \"dialout\" ];"
      echo "      in your NixOS config and re-login."
    fi
  '';
}
