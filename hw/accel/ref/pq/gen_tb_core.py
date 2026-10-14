#!/usr/bin/env python3
"""Vectors for tb_pq_core: keygen/sign through the full engine, expected bytes from the C reference."""
import os, subprocess, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_model as M, pq_asm as A
HERE = os.path.dirname(os.path.abspath(__file__))
ps = int(sys.argv[1]) if len(sys.argv) > 1 else 44
what = sys.argv[2] if len(sys.argv) > 2 else "both"
out = os.path.join(HERE, "..", "..", "tb", "vec_pq"); os.makedirs(out, exist_ok=True)
master = bytes(range(32)); msg = bytes.fromhex("48656c6c6f")
g = dict(l.split("=") for l in subprocess.run([os.path.join(HERE, "golden"), str(ps), "7", msg.hex()], capture_output=True, text=True).stdout.split())
rng = M.CRng(7); seed = rng.read(32); rnd = rng.read(32); s = A.sizes(ps); p = A.PSET[ps]
nonce = bytes(range(100, 116))                       # tb TRNG: counter bytes 100, 101, ...
blob = A.wrap_py(master, bytes.fromhex(g["sk"]), nonce)
tests = []
if what in ("both", "keygen"):
    tests.append((f"keygen{ps}", 0x64 + p, seed, 0, blob + bytes.fromhex(g["pk"])))
if what in ("both", "sign"):
    tests.append((f"sign{ps}", 0x6C + p, blob + rnd + msg, 0, bytes.fromhex(g["sig"])))
    bad = bytearray(blob); bad[40] ^= 1
    tests.append((f"sign_badtag{ps}", 0x6C + p, bytes(bad) + rnd + msg, 4, b""))
tests.append((f"ping", 0x01, b"", 0, b"TROACC01" + (A.CAPS_PQ).to_bytes(4, "big")))
with open(os.path.join(out, "index.txt"), "w") as ix:
    ix.write(f"{len(tests)}\n")
    for i, (name, cmd, pl, st, ex) in enumerate(tests):
        open(os.path.join(out, f"req_{i}.hex"), "w").write("\n".join(f"{b:02x}" for b in pl) + "\n" if pl else "00\n")
        open(os.path.join(out, f"exp_{i}.hex"), "w").write("\n".join(f"{b:02x}" for b in ex) + "\n" if ex else "00\n")
        ix.write(f"{cmd} {len(pl)} {st} {len(ex)} {name}\n")
print(len(tests), "tests for ML-DSA-%d" % ps)
