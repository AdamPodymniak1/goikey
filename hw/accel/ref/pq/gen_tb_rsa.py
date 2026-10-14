#!/usr/bin/env python3
"""Vectors for tb_pq_core (+vec=tb/vec_rsa): RSA-2048 pub / sign / bad tag, expected values from Python (RS256 = PKCS#1 v1.5, SHA-256)."""
import os, sys, random, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_asm as A
from rsa_model import SMALL_PRIMES
HERE = os.path.dirname(os.path.abspath(__file__)); out = os.path.join(HERE, "..", "..", "tb", "vec_rsa"); os.makedirs(out, exist_ok=True)
rnd = random.Random(5)
def rprime():
    while True:
        p = rnd.getrandbits(1024) | (3 << 1022) | 3
        if p % 65537 != 1 and all(p % q for q in SMALL_PRIMES) and all(pow(a, p - 1, p) == 1 for a in (2, 3, 5)): return p
p, q = rprime(), rprime(); e = 65537
dp, dq, qi = pow(e, -1, p - 1), pow(e, -1, q - 1), pow(q, -1, p); n = p * q
sk = b"".join(v.to_bytes(128, "big") for v in (p, q, dp, dq, qi))
master = bytes(range(32)); nonce = bytes(range(100, 116)); blob = A.wrap_py(master, sk, nonce)
digest = hashlib.sha256(b"hello").digest()
em = b"\x00\x01" + b"\xff" * 202 + bytes.fromhex("003031300d060960864801650304020105000420") + digest
sig = pow(int.from_bytes(em, "big"), int.from_bytes(sk[256:384], "big") * 0 + pow(e, -1, (p - 1) * (q - 1)), n).to_bytes(256, "big")
bad = bytearray(blob); bad[40] ^= 1
tests = [("rsa_pub", 0x71, blob, 0, n.to_bytes(256, "big")), ("rsa_sign", 0x72, blob + digest, 0, sig), ("rsa_sign_badtag", 0x72, bytes(bad) + digest, 4, b""),
         ("rsa_sign_badlen", 0x72, blob + digest[:31], 2, b""), ("ping", 0x01, b"", 0, b"TROACC01" + A.CAPS_PQ.to_bytes(4, "big"))]
with open(os.path.join(out, "index.txt"), "w") as ix:
    ix.write(f"{len(tests)}\n")
    for i, (name, cmd, pl, st, ex) in enumerate(tests):
        open(os.path.join(out, f"req_{i}.hex"), "w").write("\n".join(f"{b:02x}" for b in pl) + "\n" if pl else "00\n")
        open(os.path.join(out, f"exp_{i}.hex"), "w").write("\n".join(f"{b:02x}" for b in ex) + "\n" if ex else "00\n")
        ix.write(f"{cmd} {len(pl)} {st} {len(ex)} {name}\n")
print(len(tests), "RSA tests")
