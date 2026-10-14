#!/usr/bin/env python3
"""READ-ONLY: handshake once, then get_boot_info (0x10) and efuse_read (0x41) in the same session."""
import binascii, os, sys
import bflb_mcu_tool
sys.path.insert(0, os.path.dirname(bflb_mcu_tool.__file__))
from libs import bflb_img_loader, bflb_utils
port = sys.argv[1]
ld = bflb_img_loader.BflbImgLoader("bl616", "bl616", "uart")
ok, info = ld.img_get_bootinfo(port, 2000000, 2000000, "", "")
print("BOOTINFO", info)
for start, n in ((0, 128), (128, 128)):
    data = bytearray([0x41, 0]) + bflb_utils.int_to_2bytearray_l(8) + bflb_utils.int_to_4bytearray_l(start) + bflb_utils.int_to_4bytearray_l(n)
    ld.bflb_boot_if.if_write(data)
    res, rd = ld.bflb_boot_if.if_deal_response()
    print(f"EFUSE {start:3d}+{n}: {res}")
    h = binascii.hexlify(rd).decode()
    for i in range(0, len(h), 32): print(f"  {start + i // 2:3d}: {h[i:i+32]}")
ld.bflb_boot_if.if_close()
