# GoiTech GoiKey firmware for the Tang Nano 20K BL616

The BL616 on the Tang Nano 20K (board rev. 3921) normally runs Sipeed's debugger (FTDI FT2232 emulation). `goikey/`
replaces it with our own firmware, which will grow into the security-key MCU (USB to the PC, FPGA link to the crypto
accelerator in `../accel`). It is a fork of [bl616_dirtyjtag](https://github.com/pepijndevos/bl616_dirtyjtag)
(MIT, upstream commit in `goikey/UPSTREAM_COMMIT`).

USB device `1209:c0ca`, "GoiTech GoiKey":
* interface 0: DirtyJTAG v2, so the FPGA is programmed with `openFPGALoader -c dirtyJtag -b tangnano20k x.fs` (`-f` writes flash)
* interface 1: vendor bulk link (EP 0x03 OUT / 0x84 IN) to the FPGA UART (BL616 GPIO11 -> FPGA pin 70, GPIO13 <- pin 69)
  at a fixed 1.5 Mbaud. Host side: `../accel/host/goikey_link.py`; every accelerator tool accepts the port name `goikey`,
  e.g. `python3 selftest_asym.py goikey` (needs pyusb).

Verified 2026-10-14: echo up to 4000 bytes; `selftest_asym`, `selftest_pq`, `selftest_rsa` ALL PASS through GoiKey.

## Secure boot (read-only probe, `tools/readinfo.py`, `tools/readefuse.py` in UPDATE mode)
`ef_sboot_en=3`, `ef_sf_aes_mode=1` (flash AES-128), AES key in slot 2 read+write locked, no ECDSA signature,
`bootrom_protect=1` (ROM flash reads return a fixed pattern, so the factory image cannot be backed up), `usbboot_enable=1`.
The ROM only runs images at 0x0 encrypted with Sipeed's key. We use Sipeed's encrypted, unconditional bootloader
(`goikey/bl616_bootloader_0x20000_nano20k_signed.bin`, from the bl616_dirtyjtag repo) at 0x0; it always starts the
plain application at 0x20000, also when a USB host is present. eFuses are never written by any step below.

Run `./fetch_sipeed.sh` first: it downloads the two Sipeed binaries (not in git) and verifies their SHA-256.

## Build (bouffalo_sdk v2.3.16 + XuanTie gcc 2.6.1; the newest SDK changed the CherryUSB config and does not build this)
    git clone --depth 1 --branch v2.3.16 https://github.com/bouffalolab/bouffalo_sdk.git
    # toolchain: https://github.com/bouffalolab/toolchain/releases/tag/default (xuantie-gcc-riscv-v2.6.1-linux-x86_64)
    cd goikey && ln -s /path/to/bouffalo_sdk bouffalo_sdk
    export PATH=/path/to/xuantie-gcc-riscv-v2.6.1-linux-x86_64/bin:$PATH
    nix-shell -p cmake gnumake ninja python3 --run 'env -u CONFIG_SHELL make CHIP=bl616 BOARD=bl616dk'
(nix-shell exports CONFIG_SHELL, which the SDK's Kconfig step mistakes for a config symbol, hence `env -u`.)

## Flash (hold UPDATE - behind the HDMI connector - while plugging in USB; appears as "Bouffalo CDC DEMO" /dev/ttyACM0)
    T=bouffalo_sdk/tools/bflb_tools/bouffalo_flash_cube/BLFlashCommand-ubuntu
    $T --interface=uart --baudrate=2000000 --port=/dev/ttyACM0 --chipname=bl616 --cpu_id= --config=flash_app_only.ini   # app only (0x20000)
    # first install only: --config=flash_prog_cfg.ini (Sipeed bootloader at 0x0 + app)
Then unplug and plug in normally.

## Back to the factory Sipeed debugger
`recovery/bl616_fpga_partner_20kNano_2025030317.bin` (Sipeed release 2025030317; both Sipeed binaries are fetched by `fetch_sipeed.sh`, which checks their SHA-256, matches
Sipeed's published hash). In UPDATE mode: `cd recovery && $T ... --config=flash_restore_sipeed.ini`. Not yet tried.

## USB quirks of this BL616 driver (bouffalo_sdk v2.3.16, bflb_usb_v2.c)
* endpoint numbers 1..4 each own one bidirectional FIFO whose type the last opened endpoint sets: a CDC-ACM
  notification endpoint sharing a number with a bulk endpoint broke short OUT packets, hence the vendor interface.
* an OUT transfer only completes when the buffer passed to `usbd_ep_start_read` is full: read one 64-byte packet at a time.
* a packet that arrives back-to-back before the OUT DMA is re-armed is lost: the host sends one 64-byte packet per
  transfer (`goikey_link.py`). The final key firmware talks to the FPGA itself, so this only affects the dev link.

## udev (NixOS: services.udev.extraRules in /etc/nixos/configuration.nix)
    SUBSYSTEM=="usb", ATTR{idVendor}=="1209", ATTR{idProduct}=="c0ca", MODE="0666", GROUP="dialout"
