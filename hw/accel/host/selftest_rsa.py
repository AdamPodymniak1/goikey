#!/usr/bin/env python3
"""Hardware self-test of RSA-2048 (keygen, public modulus, RS256 signatures verified with `cryptography`)."""
import os, sys, time, hashlib
sys.path.insert(0, os.path.dirname(__file__))
from tro_accel import RsaAccel, AccelError, AUTH_FAIL
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes
port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
nkeys = int(sys.argv[2]) if len(sys.argv) > 2 else 1
a = RsaAccel(port, 1_500_000, timeout=900)
fails = 0
def check(name, ok, extra=""):
    global fails
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {extra}", flush=True); fails += (not ok)
name, caps = a.ping(); check("ping", name == "TROACC01" and (caps & 0x400) == 0x400, f"caps={caps:#x}")
for k in range(nkeys):
    t = time.time(); blob, n = a.rsa_generate(); dt = time.time() - t
    nn = int.from_bytes(n, "big")
    check(f"RSA-2048 keygen #{k}", len(blob) == 672 and nn.bit_length() == 2048 and nn % 2 == 1, f"({dt:.1f}s)")
    check("public modulus from blob", a.rsa_public(blob) == n)
    pub = rsa.RSAPublicNumbers(65537, nn).public_key()
    for msg in (b"hello", os.urandom(100)):
        t = time.time(); sig = a.rsa_sign_sha256(blob, hashlib.sha256(msg).digest()); dt = time.time() - t
        try: pub.verify(sig, msg, padding.PKCS1v15(), hashes.SHA256()); ok = True
        except Exception: ok = False
        check("RS256 signature verified by cryptography", ok, f"({dt:.2f}s)")
    bad = bytearray(blob); bad[40] ^= 1
    try: a.rsa_sign_sha256(bytes(bad), bytes(32)); rej = False
    except AccelError as e: rej = e.status == AUTH_FAIL
    check("tampered blob rejected", rej)
print("\nALL PASS" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
