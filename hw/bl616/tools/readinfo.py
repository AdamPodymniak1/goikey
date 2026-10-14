#!/usr/bin/env python3
"""READ-ONLY probe of a BL616 in ROM ISP (UPDATE) mode: boot info (secure-boot sign/encrypt flags) + eFuse dump.
Uses only get_boot_info (0x10) and efuse_read (0x41); never writes flash or eFuse.
usage: readinfo.py /dev/ttyACM0"""
import binascii, os, sys
import bflb_mcu_tool
PKG = os.path.dirname(bflb_mcu_tool.__file__)
sys.path.insert(0, PKG)
from libs import bflb_img_loader, bflb_utils

port = sys.argv[1]
ld = bflb_img_loader.BflbImgLoader("bl616", "bl616", "uart")
ok, info = ld.img_get_bootinfo(port, 2000000, 2000000, "", "")
if ok is not True or not info:
    sys.exit("no boot info (is the board in UPDATE mode?)")
h = info.decode() if isinstance(info, bytes) else info
print("BOOTINFO raw:", h)
print("  bootrom version:", h[0:8])
print("  sign   (eFuse sboot_sign_mode):", int(h[8:10], 16), "  (0 = no signature check)")
print("  encrypt(eFuse sf_aes_mode)    :", int(h[10:12], 16), "  (0 = flash not encrypted)")
ld.bflb_boot_if.if_close()
ok = ld.efuse_read_process(port, 2000000, 2000000)
print("efuse read ok:", ok)
