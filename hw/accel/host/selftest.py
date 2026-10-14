#!/usr/bin/env python3
"""Hardware self-test for the accelerator: every result is checked against hashlib / cryptography."""
import hashlib, hmac, os, sys, time
from cryptography.hazmat.primitives.ciphers import Cipher, algorithms, modes
from cryptography.hazmat.primitives.ciphers.aead import AESGCM
sys.path.insert(0, os.path.dirname(__file__))
from tro_accel import Accel, AccelError, AUTH_FAIL

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 1_500_000
a = Accel(port, baud)
fails = 0
def check(name, ok, extra=""):
    global fails
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {extra}")
    fails += (not ok)

name, caps = a.ping(); check("ping", name == "TROACC01", f"caps={caps:#x}")
u = a.uid(); check("uid", len(u) == 16 and u == a.uid(), u.hex())
uf = os.path.join(os.path.dirname(__file__), "..", "..", "tro", "build", "uid.hex")
if os.path.exists(uf): check("uid == build uid", open(uf).read().strip() == u.hex())
r1, r2 = a.random(64), a.random(64)
check("random", len(r1) == 64 and r1 != r2 and len(set(r1)) > 20)

for n in [0, 1, 55, 56, 64, 100, 1000, 4000]:
    d = os.urandom(n); check(f"sha256[{n}]", a.sha256(d) == hashlib.sha256(d).digest())
for kl, dl in [(1, 0), (32, 100), (64, 500), (100, 10)]:
    k, d = os.urandom(kl), os.urandom(dl)
    check(f"hmac[{kl},{dl}]", a.hmac_sha256(k, d) == hmac.new(k, d, hashlib.sha256).digest())
for pw, salt, it, dk in [(b"password", b"salt", 1, 32), (b"password", b"salt", 4096, 32),
                         (os.urandom(32), os.urandom(16), 10000, 64), (b"x" * 80, os.urandom(20), 100, 40)]:
    check(f"pbkdf2[{len(pw)},{it},{dk}]", a.pbkdf2_sha256(pw, salt, it, dk) == hashlib.pbkdf2_hmac("sha256", pw, salt, it, dk))
t0 = time.time(); got = a.pbkdf2_sha256(b"backup passphrase", b"0123456789abcdef", 200000, 32); dt = time.time() - t0
exp = hashlib.pbkdf2_hmac("sha256", b"backup passphrase", b"0123456789abcdef", 200000, 32)
t0 = time.time(); hashlib.pbkdf2_hmac("sha256", b"backup passphrase", b"0123456789abcdef", 200000, 32); dh = time.time() - t0
check("pbkdf2 200000 iterations (BackupManager)", got == exp, f"FPGA {dt:.2f}s (host CPU {dh:.2f}s)")

key = os.urandom(32); a.aes_set_key(key)
for n in [16, 64, 1024]:
    iv, pt = os.urandom(16), os.urandom(n)
    e = Cipher(algorithms.AES(key), modes.CBC(iv)).encryptor(); ct = e.update(pt) + e.finalize()
    check(f"aes-cbc[{n}]", a.aes_cbc_encrypt(iv, pt) == ct and a.aes_cbc_decrypt(iv, ct) == pt)
for al, n in [(0, 1), (0, 16), (13, 100), (0, 2000)]:
    iv, aad, pt = os.urandom(12), os.urandom(al), os.urandom(n)
    exp = AESGCM(key).encrypt(iv, pt, aad or None); ect, etag = exp[:-16], exp[-16:]
    ct, tag = a.aes_gcm_encrypt(iv, pt, aad)
    ok = ct == ect and tag == etag and a.aes_gcm_decrypt(iv, ect, etag, aad) == pt
    check(f"aes-gcm[{al},{n}]", ok)
    try: a.aes_gcm_decrypt(iv, ect, bytes([etag[0] ^ 1]) + etag[1:], aad); bad = False
    except AccelError as e: bad = (e.status == AUTH_FAIL)
    check(f"aes-gcm tamper rejected[{al},{n}]", bad)
print("\nALL PASS" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
