#!/usr/bin/env python3
"""Link-level vectors for the merged bitstream (asym + ML-DSA/RSA): checks the command-class routing and each unit through the top level.
usage: gen_vec_main.py [outdir] [only,prefixes]   (wrapped keys use the simulation MASTER key)"""
import hashlib, hmac, os, random, subprocess, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE); sys.path.insert(0, os.path.join(HERE, "pq"))
from gen_vec_link import crc16, req, rsp
import pq_model as M, pq_asm as A
from cryptography.hazmat.primitives.asymmetric import ec, ed25519
from cryptography.hazmat.primitives import serialization as ser
random.seed(99)
MASTER = bytes(range(32)); UIDB = bytes.fromhex('A1B2C3D4E5F60718293A4B5C6D7E8F00')
def rb(n): return bytes(random.randrange(256) for _ in range(n))
def wrap512(secret):
    nonce = rb(16); ks = hmac.new(MASTER, b"E" + nonce, hashlib.sha512).digest()[:32]; ct = bytes(a ^ b for a, b in zip(secret, ks))
    return nonce + ct + hmac.new(MASTER, b"M" + nonce + ct, hashlib.sha512).digest()[:16]
tests = []
def T(name, rq, ex, mask=None): tests.append((name, rq, ex, mask))
CAPS = int(os.environ.get("MAIN_CAPS", "0x7F0"), 16)
T("ping", req(0x01), rsp(0, b"TROACC01" + CAPS.to_bytes(4, "big")))
T("uid", req(0x02), rsp(0, UIDB))
T("rand", req(0x03), b"\x5A" + rsp(0, bytes(32))[1:4] + bytes(32) + bytes(2), bytes([1, 1, 1, 1]) + bytes(32) + bytes(2))
T("sym_cmd_absent", req(0x10, b"abc"), rsp(1))
T("sha512_5", req(0x50, b"hello"), rsp(0, hashlib.sha512(b"hello").digest()))
d = (random.randrange(1, 1 << 255)).to_bytes(32, "big"); sk = ec.derive_private_key(int.from_bytes(d, "big"), ec.SECP256R1()); pn = sk.public_key().public_numbers()
T("p256_pub", req(0x31, wrap512(d)), rsp(0, pn.x.to_bytes(32, "big") + pn.y.to_bytes(32, "big")))
seed = rb(32); esk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
T("ed_sign", req(0x42, wrap512(seed) + b"abc"), rsp(0, esk.sign(b"abc")))
# --- ML-DSA-44 (explicit seed keygen + explicit-rnd sign) and RSA, expected values from the C reference / Python ---
msg = bytes.fromhex("48656c6c6f"); g = dict(l.split("=") for l in subprocess.run([os.path.join(HERE, "pq", "golden"), "44", "7", msg.hex()], capture_output=True, text=True).stdout.split())
rng = M.CRng(7); pseed = rng.read(32); rnd = rng.read(32); s = A.sizes(44)
nonce = bytes(range(100, 116))
blob = A.wrap_py(MASTER, bytes.fromhex(g["sk"]), nonce)
kg_exp = rsp(0, bytes(len(blob)) + bytes.fromhex(g["pk"]))
kg_mask = bytes([1, 1, 1, 1]) + bytes(len(blob)) + bytes([1]) * len(bytes.fromhex(g["pk"])) + bytes(2)      # the blob nonce comes from the TRNG (and the CRC covers it): check the public key only
T("mldsa44_keygen", req(0x64, pseed), kg_exp, kg_mask)
T("mldsa44_sign", req(0x6C, blob + rnd + msg), rsp(0, bytes.fromhex(g["sig"])))
rp = random.Random(5)
def rprime():
    from rsa_model import SMALL_PRIMES
    while True:
        p = rp.getrandbits(1024) | (3 << 1022) | 3
        if p % 65537 != 1 and all(p % q for q in SMALL_PRIMES) and all(pow(a, p - 1, p) == 1 for a in (2, 3, 5)): return p
p, q = rprime(), rprime(); e = 65537
sk_rsa = b"".join(v.to_bytes(128, "big") for v in (p, q, pow(e, -1, p - 1), pow(e, -1, q - 1), pow(q, -1, p)))
rblob = A.wrap_py(MASTER, sk_rsa, nonce)
T("rsa_pub", req(0x71, rblob), rsp(0, (p * q).to_bytes(256, "big")))
T("bad_len", req(0x32, rb(10)), rsp(2))
only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
if only: tests = [t for t in tests if any(t[0].startswith(o) for o in only)]
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "tb", "vec_main")
os.makedirs(out, exist_ok=True)
with open(f"{out}/index.txt", "w") as ix:
    ix.write(f"{len(tests)}\n")
    for i, (name, rq, ex, mask) in enumerate(tests):
        open(f"{out}/req_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in rq) + "\n")
        open(f"{out}/exp_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in ex) + "\n")
        mk = mask if mask is not None else bytes([1]) * len(ex)
        open(f"{out}/msk_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in mk) + "\n")
        ix.write(f"{len(rq)} {len(ex)} {name}\n")
print(len(tests), "link tests for the merged bitstream")
