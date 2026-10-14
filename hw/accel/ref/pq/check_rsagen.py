#!/usr/bin/env python3
"""Check an RSA keygen response dumped by tb_pq_core (+dump): usage check_rsagen.py tb/vec_rsagen/got_0.hex"""
import hashlib, sys
sys.path.insert(0, __import__("os").path.dirname(__file__))
import pq_asm as A
from cryptography.hazmat.primitives.asymmetric import rsa, padding
from cryptography.hazmat.primitives import hashes
d = bytes(int(x, 16) for x in open(sys.argv[1]).read().split())
assert len(d) == 928, len(d)
blob, n = d[:672], int.from_bytes(d[672:], "big")
master = bytes(range(32)); nonce = blob[:16]
ks = hashlib.shake_256(b"E" + master + nonce).digest(640); sk = bytes(a ^ b for a, b in zip(blob[16:656], ks))
tag = hashlib.shake_256(b"M" + master + nonce + blob[16:656]).digest(16); assert tag == blob[656:], "tag"
p, q, dp, dq, qi = (int.from_bytes(sk[128 * i:128 * i + 128], "big") for i in range(5))
assert p * q == n and n.bit_length() == 2048
assert p % 4 == 3 and q % 4 == 3 and p >> 1022 == 3 and q >> 1022 == 3
for r in (p, q):
    assert all(pow(a, r - 1, r) == 1 for a in (2, 3, 5, 7, 11, 13)), "not prime"
e = 65537
assert (dp * e) % (p - 1) == 1 and (dq * e) % (q - 1) == 1 and (qi * q) % p == 1
key = rsa.RSAPrivateNumbers(p, q, pow(e, -1, (p - 1) * (q - 1)), dp, dq, qi, rsa.RSAPublicNumbers(e, n)).private_key()
sig = key.sign(b"x", padding.PKCS1v15(), hashes.SHA256()); key.public_key().verify(sig, b"x", padding.PKCS1v15(), hashes.SHA256())
print("RSA keygen output OK: 2048-bit n, p/q probable primes, CRT parameters consistent, tag valid")
