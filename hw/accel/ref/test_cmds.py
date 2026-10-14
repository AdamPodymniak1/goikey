#!/usr/bin/env python3
"""Run every command flow through the reference interpreter and check it against `cryptography`."""
import hashlib, hmac, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import ecc_asm as E
from ecc_model import *
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, utils
from cryptography.hazmat.primitives import hashes, serialization as ser

A = E.build(); code = A.link()
UID = bytes(range(0xA0, 0xB0)); rng = random.Random(42)
def cmd(c, payload=b""):
    dev = E.Dev(payload, UID, rng)
    regs, flag, steps = E.run(code, A.entries[E.CMD_TABLE[c]], {}, dev=dev)
    st, ln = dev.fin
    return st, bytes(dev.tx[:ln]), steps
MASTER = E.MASTER
def wrap_py(secret, nonce):
    ks = hmac.new(MASTER, b"E" + nonce, hashlib.sha512).digest()[:32]
    ct = bytes(a ^ b for a, b in zip(secret, ks))
    tag = hmac.new(MASTER, b"M" + nonce + ct, hashlib.sha512).digest()[:16]
    return nonce + ct + tag
def unwrap_py(blob):
    nonce, ct, tag = blob[:16], blob[16:48], blob[48:64]
    assert hmac.new(MASTER, b"M" + nonce + ct, hashlib.sha512).digest()[:16] == tag
    ks = hmac.new(MASTER, b"E" + nonce, hashlib.sha512).digest()[:32]
    return bytes(a ^ b for a, b in zip(ct, ks))
ok = True
def check(name, cond, extra=""):
    global ok; ok &= bool(cond); print(f"[{'PASS' if cond else 'FAIL'}] {name} {extra}")

st, r, _ = cmd(1); check("ping", st == 0 and r[:8] == b"TROACC01" and len(r) == 12)
st, r, _ = cmd(2); check("uid", st == 0 and r == UID)
st, r, _ = cmd(3); r2 = cmd(3)[1]; check("rand", st == 0 and len(r) == 32 and r != r2)
d = os.urandom(300); st, r, _ = cmd(0x50, d); check("sha512", r == hashlib.sha512(d).digest())
st, r, _ = cmd(0x50, b""); check("sha512 empty", r == hashlib.sha512(b"").digest())

# P-256
st, r, steps = cmd(0x30); check("p256 gen", st == 0 and len(r) == 128, f"({steps} instr)")
blob, pub = r[:64], r[64:]
d = int.from_bytes(unwrap_py(blob), "big")
pn = ec.derive_private_key(d, ec.SECP256R1()).public_key().public_numbers()
check("p256 gen: pub matches blob's key", pub == pn.x.to_bytes(32, "big") + pn.y.to_bytes(32, "big"))
st, r, _ = cmd(0x31, blob); check("p256 pub", st == 0 and r == pub)
bad = bytearray(blob); bad[63] ^= 1; st, r, _ = cmd(0x31, bytes(bad)); check("p256 pub: tampered blob rejected", st == 4 and r == b"")
dig = hashlib.sha256(b"hello").digest()
st, r, _ = cmd(0x32, blob + dig); check("p256 sign", st == 0 and len(r) == 64)
sk = ec.derive_private_key(d, ec.SECP256R1())
sk.public_key().verify(utils.encode_dss_signature(int.from_bytes(r[:32], "big"), int.from_bytes(r[32:], "big")), dig,
                       ec.ECDSA(utils.Prehashed(hashes.SHA256()))); check("p256 sign: verified by cryptography", True)
st, v, _ = cmd(0x34, dig + r + pub); check("p256 verify ok", st == 0)
st, v, _ = cmd(0x34, bytes([dig[0] ^ 1]) + dig[1:] + r + pub); check("p256 verify rejects wrong digest", st == 4)
peer = ec.generate_private_key(ec.SECP256R1()); pp = peer.public_key().public_numbers()
st, r, _ = cmd(0x33, blob + pp.x.to_bytes(32, "big") + pp.y.to_bytes(32, "big"))
check("p256 ecdh", st == 0 and r == sk.exchange(ec.ECDH(), peer.public_key()))
st, r, _ = cmd(0x33, blob + pp.x.to_bytes(32, "big") + (pp.y ^ 1).to_bytes(32, "big")); check("p256 ecdh rejects off-curve", st == 6)
raw = os.urandom(32); raw = bytes([raw[0] & 0x7F]) + raw[1:]
st, r, _ = cmd(0x35, raw); check("p256 wrap", st == 0 and unwrap_py(r) == raw)
st, r, _ = cmd(0x35, bytes(32)); check("p256 wrap rejects zero key", st == 6)
st, r, _ = cmd(0x32, blob); check("bad length rejected", st == 2)

# Ed25519
st, r, steps = cmd(0x40); check("ed gen", st == 0 and len(r) == 96, f"({steps} instr)")
eblob, epub = r[:64], r[64:]
seed = unwrap_py(eblob); sk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
check("ed gen: pub matches", epub == sk.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw))
st, r, _ = cmd(0x41, eblob); check("ed pub", st == 0 and r == epub)
for m in (b"", b"abc", os.urandom(200)):
    st, r, _ = cmd(0x42, eblob + m); check(f"ed sign[{len(m)}] identical to cryptography", st == 0 and r == sk.sign(m))
seed = os.urandom(32); st, r, _ = cmd(0x43, seed); check("ed wrap", st == 0 and unwrap_py(r) == seed)
print("\nALL PASS" if ok else "\nFAILURES"); sys.exit(0 if ok else 1)
