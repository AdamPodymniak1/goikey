#!/usr/bin/env python3
"""Generate link-level test vectors (request/expected-response frames) for tb_accel_top."""
import hashlib, hmac, os, random, sys
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
random.seed(2024)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
def crc16(d, c=0xFFFF):
    for b in d:
        c ^= b << 8
        for _ in range(8): c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
    return c
def req(cmd, pl=b""): 
    body = bytes([cmd]) + len(pl).to_bytes(2, "little") + pl
    return b"\xA5" + body + crc16(body).to_bytes(2, "little")
def rsp(status, pl=b""):
    body = bytes([status]) + len(pl).to_bytes(2, "little") + pl
    return b"\x5A" + body + crc16(body).to_bytes(2, "little")
def main():
    UID = bytes.fromhex("A1B2C3D4E5F60718293A4B5C6D7E8F00")
    tests = []   # (name, request, expected, mask or None)
    tests.append(("ping", req(1), rsp(0, b"TROACC01" + (0xF).to_bytes(4, "big")), None))
    tests.append(("uid", req(2), rsp(0, UID), None))
    for n in [1, 33, 100]:
        e = rsp(0, bytes(n)); m = bytes([1,1,1,1]) + bytes(n) + bytes(2)
        tests.append((f"rand{n}", req(3, n.to_bytes(2, "little")), b"\x5A" + e[1:4] + bytes(n) + bytes(2), bytes([1,1,1,1]) + bytes(n) + bytes(2)))
    for n in [0, 3, 64, 200, 1000]:
        d = rb(n); tests.append((f"sha{n}", req(0x10, d), rsp(0, hashlib.sha256(d).digest()), None))
    for kl, dl in [(32, 50), (1, 0), (64, 130)]:
        k, d = rb(kl), rb(dl)
        tests.append((f"hmac{kl}_{dl}", req(0x11, bytes([kl]) + k + d), rsp(0, hmac.new(k, d, hashlib.sha256).digest()), None))
    for pw, salt, it, dk in [(8,16,1,32),(32,16,3,32),(16,40,50,64),(64,60,7,100),(5,13,1,20)]:
        p, s = rb(pw), rb(salt)
        pl = it.to_bytes(4,"little") + dk.to_bytes(2,"little") + bytes([pw]) + p + s
        tests.append((f"pbkdf2_{pw}_{salt}_{it}_{dk}", req(0x12, pl), rsp(0, hashlib.pbkdf2_hmac("sha256", p, s, it, dk)), None))
    key = rb(32)
    def aesop(mode, iv, aad, data, tag=b""): return req(0x21, bytes([mode]) + iv + len(aad).to_bytes(2,"little") + len(data).to_bytes(2,"little") + aad + data + tag)
    tests.append(("aes_nokey", aesop(2, bytes(16), b"", bytes(16)), rsp(7), None))
    tests.append(("aes_setkey", req(0x20, key), rsp(0), None))
    for dl in [16, 64]:
        pt = rb(dl)
        enc = Cipher(algorithms.AES(key), modes.ECB()).encryptor(); ct = enc.update(pt) + enc.finalize()
        tests.append((f"ecb_enc{dl}", aesop(0, rb(16), b"", pt), rsp(0, ct), None))
        tests.append((f"ecb_dec{dl}", aesop(1, rb(16), b"", ct), rsp(0, pt), None))
    for dl in [16, 48, 160]:
        iv, pt = rb(16), rb(dl)
        enc = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor(); ct = enc.update(pt) + enc.finalize()
        tests.append((f"cbc_enc{dl}", aesop(2, iv, b"", pt), rsp(0, ct), None))
        tests.append((f"cbc_dec{dl}", aesop(3, iv, b"", ct), rsp(0, pt), None))
    for al, dl in [(0, 5), (0, 16), (7, 33), (0, 100), (20, 0), (33, 47), (16, 1000), (0, 0)]:
        iv12, aad, pt = rb(12), rb(al), rb(dl)
        out = AESGCM(key).encrypt(iv12, pt, aad or None); ct, tag = out[:-16], out[-16:]
        iv = iv12 + bytes(4)
        tests.append((f"gcm_enc{al}_{dl}", aesop(4, iv, aad, pt), rsp(0, ct + tag), None))
        tests.append((f"gcm_dec{al}_{dl}", aesop(5, iv, aad, ct, tag), rsp(0, pt), None))
        bad = bytes([tag[0] ^ 1]) + tag[1:]
        tests.append((f"gcm_bad{al}_{dl}", aesop(5, iv, aad, ct, bad), rsp(4), None))
        if dl:
            badc = bytes([ct[-1] ^ 0x80]) if dl == 1 else ct[:-1] + bytes([ct[-1] ^ 0x80])
            tests.append((f"gcm_badct{al}_{dl}", aesop(5, iv, aad, badc, tag), rsp(4), None))
            tests.append((f"gcm_badtag15_{al}_{dl}", aesop(5, iv, aad, ct, tag[:15] + bytes([tag[15] ^ 0x40])), rsp(4), None))
    # negative tests
    tests.append(("bad_cmd", req(0x7E), rsp(1), None))
    tests.append(("bad_len", req(0x20, b"x"*5), rsp(2), None))
    tests.append(("bad_pbkdf2", req(0x12, (0).to_bytes(4,"little") + (32).to_bytes(2,"little") + bytes([0]) + b"s"), rsp(6), None))
    bad = bytearray(req(0x10, b"hello")); bad[-1] ^= 0xFF
    tests.append(("bad_crc", bytes(bad), rsp(3), None))
    tests.append(("after_bad_crc", req(0x10, b"ok"), rsp(0, hashlib.sha256(b"ok").digest()), None))

    out = sys.argv[1] if len(sys.argv) > 1 else "tb/vec"
    os.makedirs(out, exist_ok=True)
    with open(f"{out}/index.txt", "w") as ix:
        ix.write(f"{len(tests)}\n")
        for i, (name, rq, ex, mask) in enumerate(tests):
            open(f"{out}/req_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in rq) + "\n")
            open(f"{out}/exp_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in ex) + "\n")
            m = mask if mask is not None else bytes([1]) * len(ex)
            open(f"{out}/msk_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in m) + "\n")
            ix.write(f"{len(rq)} {len(ex)} {name}\n")
    print(len(tests), "link tests")

if __name__ == "__main__":
    main()
