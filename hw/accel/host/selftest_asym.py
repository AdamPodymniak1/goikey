#!/usr/bin/env python3
"""Hardware self-test for the asymmetric accelerator bitstream (every result checked by `cryptography`)."""
import hashlib, os, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, utils
from cryptography.hazmat.primitives import hashes, serialization as ser
from tro_accel import AsymAccel, AccelError, AUTH_FAIL

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
baud = int(sys.argv[2]) if len(sys.argv) > 2 else 1_500_000
a = AsymAccel(port, baud, timeout=30)
fails = 0
def check(name, ok, extra=""):
    global fails
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {extra}", flush=True); fails += (not ok)
def timed(f, *args):
    t = time.time(); r = f(*args); return r, time.time() - t

name, caps = a.ping(); check("ping", name == "TROACC01", f"caps={caps:#x}")
u = a.uid(); check("uid", len(u) == 16 and u == a.uid(), u.hex())
uf = os.path.join(os.path.dirname(__file__), "..", "..", "tro", "build", "uid.hex")
if os.path.exists(uf): check("uid == build uid", open(uf).read().strip() == u.hex())
r1, r2 = a.random32(), a.random32(); check("random", r1 != r2 and len(set(r1)) > 12)
for n in (0, 1, 127, 128, 129, 1000):
    d = os.urandom(n); check(f"sha512[{n}]", a.sha512(d) == hashlib.sha512(d).digest())

# ---------- P-256 ----------
(blob, pub), dt = timed(a.p256_generate); check("p256 generate", len(blob) == 64 and len(pub) == 64, f"({dt:.2f}s)")
ec.EllipticCurvePublicNumbers(int.from_bytes(pub[:32], "big"), int.from_bytes(pub[32:], "big"), ec.SECP256R1()).public_key()  # on-curve check by cryptography
check("p256 public key on curve (cryptography)", True)
check("p256 public from blob", a.p256_public(blob) == pub)
pk = ec.EllipticCurvePublicNumbers(int.from_bytes(pub[:32], "big"), int.from_bytes(pub[32:], "big"), ec.SECP256R1()).public_key()
for i in range(3):
    msg = os.urandom(50); dig = hashlib.sha256(msg).digest()
    sig, dt = timed(a.p256_sign, blob, dig)
    pk.verify(utils.encode_dss_signature(int.from_bytes(sig[:32], "big"), int.from_bytes(sig[32:], "big")), msg, ec.ECDSA(hashes.SHA256()))
    check(f"p256 sign #{i} verified by cryptography", True, f"({dt:.2f}s)")
check("p256 FPGA verify accepts", a.p256_verify(dig, sig, pub))
check("p256 FPGA verify rejects", not a.p256_verify(bytes([dig[0] ^ 1]) + dig[1:], sig, pub))
peer = ec.generate_private_key(ec.SECP256R1()); pp = peer.public_key().public_numbers()
x, dt = timed(a.p256_ecdh, blob, pp.x.to_bytes(32, "big") + pp.y.to_bytes(32, "big"))
# peer computes with our public key
shared_peer = peer.exchange(ec.ECDH(), pk); check("p256 ecdh matches peer", x == shared_peer, f"({dt:.2f}s)")
bad = bytearray(blob); bad[20] ^= 1
try: a.p256_public(bytes(bad)); rej = False
except AccelError as e: rej = e.status == AUTH_FAIL
check("tampered blob rejected", rej)
mine = ec.generate_private_key(ec.SECP256R1()); raw = mine.private_numbers().private_value.to_bytes(32, "big")
wb = a.p256_wrap(raw); wp = mine.public_key().public_numbers()
check("p256 import existing key", a.p256_public(wb) == wp.x.to_bytes(32, "big") + wp.y.to_bytes(32, "big"))

# ---------- Ed25519 ----------
(eblob, epub), dt = timed(a.ed25519_generate); check("ed25519 generate", len(eblob) == 64 and len(epub) == 32, f"({dt:.2f}s)")
check("ed25519 public from blob", a.ed25519_public(eblob) == epub)
ek = ed25519.Ed25519PublicKey.from_public_bytes(epub)
for m in (b"", b"abc", os.urandom(300)):
    sig, dt = timed(a.ed25519_sign, eblob, m); ek.verify(sig, m); check(f"ed25519 sign[{len(m)}] verified by cryptography", True, f"({dt:.2f}s)")
seed = os.urandom(32); sk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
wb = a.ed25519_wrap(seed)
check("ed25519 import seed -> same public key", a.ed25519_public(wb) == sk.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw))
check("ed25519 signature identical to cryptography", a.ed25519_sign(wb, b"deterministic") == sk.sign(b"deterministic"))
print("\nALL PASS" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
