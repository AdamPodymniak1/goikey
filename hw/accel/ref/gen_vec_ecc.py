#!/usr/bin/env python3
"""Link-level vectors for the asymmetric profile (HAS_ECC=1); wrapped keys use the simulation MASTER key."""
import hashlib, hmac, os, random, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
from gen_vec_link import crc16, req, rsp
from cryptography.hazmat.primitives.asymmetric import ec, ed25519, utils
from cryptography.hazmat.primitives import hashes, serialization as ser
random.seed(77)
MASTER = bytes(range(32))                                   # simulation default (ecc_asm.MASTER)
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
UIDB = bytes.fromhex('A1B2C3D4E5F60718293A4B5C6D7E8F00')
def rb(n): return bytes(random.randrange(256) for _ in range(n))
def wrap(secret, nonce=None):
    nonce = nonce or rb(16)
    ks = hmac.new(MASTER, b"E" + nonce, hashlib.sha512).digest()[:32]
    ct = bytes(a ^ b for a, b in zip(secret, ks))
    tag = hmac.new(MASTER, b"M" + nonce + ct, hashlib.sha512).digest()[:16]
    return nonce + ct + tag
tests = []
def T(name, rq, ex, mask=None): tests.append((name, rq, ex, mask))
def nomask_payload(status, n):          # status + length checked, payload & crc ignored
    return (b"\x5A" + bytes([status]) + n.to_bytes(2, "little") + bytes(n) + b"\0\0",
            bytes([1, 1, 1, 1]) + bytes(n) + bytes(2))
T("ping", req(0x01), rsp(0, b"TROACC01" + (0xF0).to_bytes(4, "big")))
T("uid", req(0x02), rsp(0, UIDB))
e, m = nomask_payload(0, 32); T("rand", req(0x03), e, m)
for n in (0, 5, 130):
    d = rb(n); T(f"sha512_{n}", req(0x50, d), rsp(0, hashlib.sha512(d).digest()))
d = random.randrange(1, ec.SECP256R1().key_size and (1 << 255)); d = d.to_bytes(32, "big")
dn = int.from_bytes(d, "big"); sk = ec.derive_private_key(dn, ec.SECP256R1()); pn = sk.public_key().public_numbers()
pub = pn.x.to_bytes(32, "big") + pn.y.to_bytes(32, "big")
blob = wrap(d)
T("p256_pub", req(0x31, blob), rsp(0, pub))
peer = ec.generate_private_key(ec.SECP256R1()); pp = peer.public_key().public_numbers()
T("p256_ecdh", req(0x33, blob + pp.x.to_bytes(32, "big") + pp.y.to_bytes(32, "big")), rsp(0, sk.exchange(ec.ECDH(), peer.public_key())))
bad = bytearray(blob); bad[60] ^= 1
T("p256_pub_badtag", req(0x31, bytes(bad)), rsp(4))
msg = b"link test"; dig = hashlib.sha256(msg).digest()
sig = sk.sign(dig, ec.ECDSA(utils.Prehashed(hashes.SHA256()))); r, s = utils.decode_dss_signature(sig)
rs = r.to_bytes(32, "big") + s.to_bytes(32, "big")
T("p256_verify_ok", req(0x34, dig + rs + pub), rsp(0))
T("p256_verify_bad", req(0x34, bytes([dig[0] ^ 1]) + dig[1:] + rs + pub), rsp(4))
seed = rb(32); esk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
epub = esk.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw)
eblob = wrap(seed)
T("ed_pub", req(0x41, eblob), rsp(0, epub))
for m in (b"", b"abc", rb(150)):
    T(f"ed_sign_{len(m)}", req(0x42, eblob + m), rsp(0, esk.sign(m)))
# random-nonce commands: status + length only
e, m = nomask_payload(0, 128); T("p256_gen", req(0x30), e, m)
e, m = nomask_payload(0, 64);  T("p256_sign", req(0x32, blob + dig), e, m)
e, m = nomask_payload(0, 64);  T("p256_wrap", req(0x35, d), e, m)
e, m = nomask_payload(0, 96);  T("ed_gen", req(0x40), e, m)
T("bad_len", req(0x32, blob), rsp(2))
only = sys.argv[2].split(",") if len(sys.argv) > 2 else None
if only: tests = [t for t in tests if any(t[0].startswith(o) for o in only)]
out = sys.argv[1] if len(sys.argv) > 1 else "tb/vec_ecc"
os.makedirs(out, exist_ok=True)
with open(f"{out}/index.txt", "w") as ix:
    ix.write(f"{len(tests)}\n")
    for i, (name, rq, ex, mask) in enumerate(tests):
        open(f"{out}/req_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in rq) + "\n")
        open(f"{out}/exp_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in ex) + "\n")
        mk = mask if mask is not None else bytes([1]) * len(ex)
        open(f"{out}/msk_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in mk) + "\n")
        ix.write(f"{len(rq)} {len(ex)} {name}\n")
print(len(tests), "ECC link tests")
