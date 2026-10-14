#!/usr/bin/env python3
"""Link-level vectors for the hash-only command processor (hash_cmd): SHA-256, HMAC-SHA256, PBKDF2; AES commands must be rejected."""
import hashlib, hmac, os, random, sys
HERE = os.path.dirname(os.path.abspath(__file__)); sys.path.insert(0, HERE)
from gen_vec_link import crc16, req, rsp
random.seed(31)
def rb(n): return bytes(random.randrange(256) for _ in range(n))
tests = []
def T(name, rq, ex): tests.append((name, rq, ex))
for n in (0, 3, 64, 200, 1000):
    d = rb(n); T(f"sha{n}", req(0x10, d), rsp(0, hashlib.sha256(d).digest()))
for kl, dl in [(32, 50), (1, 0), (64, 130), (0, 7)]:
    k, d = rb(kl), rb(dl); T(f"hmac{kl}_{dl}", req(0x11, bytes([kl]) + k + d), rsp(0, hmac.new(k, d, hashlib.sha256).digest()))
for pw, salt, it, dk in [(8, 16, 1, 32), (32, 16, 3, 32), (16, 40, 50, 64), (64, 60, 7, 100), (5, 13, 1, 20), (0, 4, 2, 32)]:
    p, s = rb(pw), rb(salt)
    T(f"pbkdf2_{pw}_{salt}_{it}_{dk}", req(0x12, it.to_bytes(4, "little") + dk.to_bytes(2, "little") + bytes([pw]) + p + s), rsp(0, hashlib.pbkdf2_hmac("sha256", p, s, it, dk)))
T("aes_absent", req(0x20, rb(32)), rsp(1))
T("aes_op_absent", req(0x21, rb(40)), rsp(1))
T("bad_cmd", req(0x7E), rsp(1))
T("bad_hmac_klen", req(0x11, bytes([65]) + rb(80)), rsp(6))
T("bad_hmac_len", req(0x11, b""), rsp(2))
T("bad_pbkdf2", req(0x12, (0).to_bytes(4, "little") + (32).to_bytes(2, "little") + bytes([0]) + b"s"), rsp(6))
T("bad_pbkdf2_len", req(0x12, b"short"), rsp(2))
T("after", req(0x10, b"ok"), rsp(0, hashlib.sha256(b"ok").digest()))
out = sys.argv[1] if len(sys.argv) > 1 else os.path.join(HERE, "..", "tb", "vec_hash")
os.makedirs(out, exist_ok=True)
with open(f"{out}/index.txt", "w") as ix:
    ix.write(f"{len(tests)}\n")
    for i, (name, rq, ex) in enumerate(tests):
        open(f"{out}/req_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in rq) + "\n")
        open(f"{out}/exp_{i}.hex", "w").write("\n".join(f"{b:02x}" for b in ex) + "\n")
        open(f"{out}/msk_{i}.hex", "w").write("\n".join("01" for _ in ex) + "\n")
        ix.write(f"{len(rq)} {len(ex)} {name}\n")
print(len(tests), "hash_cmd link tests")
