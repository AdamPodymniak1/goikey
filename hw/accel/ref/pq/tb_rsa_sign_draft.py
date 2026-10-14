#!/usr/bin/env python3
"""Op-level test of the pq_rsa RTL vs the interpreter: python3 tb_rsa_ops.py [seed]  (run inside nix-shell)."""
import sys, os, random, subprocess, hashlib
sys.path.insert(0, os.path.dirname(__file__))
import pq_asm as A
from rsa_model import SMALL_PRIMES
from cryptography.hazmat.primitives.asymmetric import rsa
HERE = os.path.dirname(os.path.abspath(__file__)); ACC = os.path.join(HERE, "..", "..")
seed = int(sys.argv[1]) if len(sys.argv) > 1 else 1
rnd = random.Random(seed)
def rprime(bits=1024):
    while True:
        p = rnd.getrandbits(bits) | (3 << (bits - 2)) | 3
        if all(p % q for q in SMALL_PRIMES) and pow(2, p - 1, p) == 1 and pow(3, p - 1, p) == 1: return p
P = rprime(); Q = rprime(); e = 65537
dp, dq, qi = pow(e, -1, P - 1), pow(e, -1, Q - 1), pow(Q, -1, P)
d = (P - 1) * (Q - 1)
em = int.from_bytes(b"\x00\x01" + b"\xff" * 202 + bytes.fromhex("003031300d060960864801650304020105000420") + hashlib.sha256(b"hello").digest(), "big")
regs_init = {0: P, 1: Q, 2: dp, 3: dq, 4: qi, 5: em >> 1024, 6: em & ((1 << 1024) - 1)}
ops = []
RX, TX = A.RX, A.TX
def op(name, a=0, b=0, c=0, d=0, *imm): ops.append((name, a, b, c, d) + imm)
for r in range(7): op("RLDB", r, 0, 0, 0, A.desc(RX, 128 * r, 128))
PR, R2, T, U, MP, X, ONE, E, SQ, SP, DX, D, H = 7, 8, 9, 10, 11, 12, 13, 14, 15, 7, 13, 9, 10
EMH, EML, PP, QQ, DPR, DQR, QIR = 5, 6, 0, 1, 2, 3, 4
op("RSETI", E, 0, 0, 0, 65537); op("RSETI", ONE, 0, 0, 0, 1)
def crt_half(prime, dd, out):
    op("RMOV_", PR, prime); op("RMSEL", PR); op("RR2", R2)
STEPS = 0
# --- oracle ---
rx = bytearray(8192)
for r, v in regs_init.items(): rx[128 * r:128 * r + 128] = v.to_bytes(128, "big")
tk = [(0x9E3779B1 * (k + 1)) & 0xFFFFFFFF for k in range(40)]    # words delivered by the TB TRNG model
trng_words = tk[:32]
rng_int = sum(w << (32 * j) for j, w in enumerate(trng_words))
dev = A.Dev(bytes(rx)); dev.rx[:] = rx; dev.trng = lambda n: rng_int.to_bytes(128, "big")
for o in ops:
    A_ = A.Asm(0); A_.op(*o); A_.op("FIN", 0, 0, 0, 0, 0)
    A.run(A_.link(), 0, dev)
oracle_tx = bytes(dev.tx[:2048])
# --- RTL ---
w = [len(ops)]
for o in ops:
    imm = o[5] if len(o) > 5 else 0
    w += [A.OPS[o[0]], o[1], o[2], o[3], o[4], imm & 0xFFFFFFFF]
sc = os.environ.get("SCRATCH", "."); os.makedirs(sc, exist_ok=True)
open(f"{sc}/ops.hex", "w").write("\n".join(f"{x:08x}" for x in w) + "\n")
open(f"{sc}/rx.hex", "w").write("\n".join(f"{b:02x}" for b in rx) + "\n")
subprocess.run(["iverilog", "-g2012", "-DSIM_FAST_TRNG", "-I", os.path.join(ACC, "rtl_pq"), "-o", f"{sc}/rsa_ops.vvp", os.path.join(ACC, "tb", "tb_pq_rsa.v"), os.path.join(ACC, "rtl_pq", "pq_rsa.v")], check=True)
out = subprocess.run(["vvp", f"{sc}/rsa_ops.vvp"], cwd=sc, capture_output=True, text=True).stdout
print(out.strip().splitlines()[-1])
txm = [int(l, 16) for l in open(f"{sc}/tx_out.hex").read().splitlines() if l and not l.startswith("//")]
rtl_tx = bytes(txm[:2048])
names = [o[0] for o in ops]
fl = [l.split() for l in open(f"{sc}/flags.txt")]
rtl_flags = [int(l[2]) for l in fl if int(l[1], 16) in (0xAB, 0xAC, 0xAE)]
print("oracle flags", dev.flagtrace, "rtl flags", rtl_flags)
for l in fl:
    if int(l[1], 16) >= 0xA5 and int(l[1], 16) != 0xA1 and int(l[1], 16) != 0xA0: print("  op", l[0], names[int(l[0])], "cycles", l[3])
bad = 0
for r in range(16):
    a, b = oracle_tx[128 * r:128 * r + 128], rtl_tx[128 * r:128 * r + 128]
    if r == 14 and False: continue
    print(f"r{r:2d}", "OK" if a == b else "MISMATCH"); bad += a != b
print("flags", "OK" if dev.flagtrace == rtl_flags else "MISMATCH"); bad += dev.flagtrace != rtl_flags
sys.exit(1 if bad else 0)
