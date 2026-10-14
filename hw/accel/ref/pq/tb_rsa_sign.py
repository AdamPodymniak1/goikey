#!/usr/bin/env python3
"""Run the RSA ops of the microcoded 'sign' program on the pq_rsa RTL (key already decrypted in RX, EM in SC) and compare with the interpreter."""
import sys, os, random, subprocess, hashlib
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_asm as A
HERE = os.path.dirname(os.path.abspath(__file__)); ACC = os.path.join(HERE, "..", "..")
d = os.path.join(ACC, "tb", "vec_rsa")
rd = lambda f: bytes(int(x, 16) for x in open(os.path.join(d, f)).read().split())
req = rd("req_1.hex"); exp = rd("exp_1.hex")
master = bytes(range(32)); blob = req[:672]; nonce = blob[:16]
ks = __import__("hashlib").shake_256(b"E" + master + nonce).digest(640); sk = bytes(a ^ b for a, b in zip(blob[16:656], ks))
digest = req[672:704]
em = b"\x00\x01" + b"\xff" * 202 + bytes.fromhex("003031300d060960864801650304020105000420") + digest
prog = A.prog_rsa(0); code = prog.code
# collect R ops of the sign program (from the first RLDB after the EM construction up to FIN)
pc = prog.entries["sign"]; ops = []; started = False
while True:
    w = code[pc]; opn = A.REV[w >> 24]; n = A.IMMN.get(opn, 0); imm = code[pc + 1:pc + 1 + n]
    if opn == "FIN": break
    if opn in ("JMP", "JF", "JNF"): pc += 1 + n; continue
    if 0xA0 <= (w >> 24) <= 0xB8: ops.append((opn, (w >> 18) & 63, (w >> 12) & 63, (w >> 6) & 63, w & 63) + tuple(imm))
    pc += 1 + n
print(len(ops), "ops")
rx = bytearray(8192); rx[16:656] = sk; sc = bytearray(2048); sc[0:256] = em
dev = A.Dev(bytes(rx)); dev.rx[:] = rx; dev.sc[:256] = em
trace = []
for o in ops:
    P_ = A.Asm(0); P_.op(*o); P_.op("FIN", 0, 0, 0, 0, 0); A.run(P_.link(), 0, dev); trace.append(list(dev.big[:16]))
oracle = bytes(dev.tx[:256]); print("oracle==exp", oracle == exp)
w = [len(ops)]
for o in ops: w += [A.OPS[o[0]], o[1], o[2], o[3], o[4], (o[5] if len(o) > 5 else 0) & 0xFFFFFFFF]
sd = os.environ.get("SCRATCH", "."); os.makedirs(sd, exist_ok=True)
open(f"{sd}/ops.hex", "w").write("\n".join(f"{x:08x}" for x in w) + "\n")
open(f"{sd}/rx.hex", "w").write("\n".join(f"{b:02x}" for b in rx) + "\n")
open(f"{sd}/sc.hex", "w").write("\n".join(f"{b:02x}" for b in sc) + "\n")
subprocess.run(["iverilog", "-g2012", "-I", os.path.join(ACC, "rtl_pq"), "-I", os.path.join(ACC, "rtl"), "-o", f"{sd}/rsa_sign.vvp", os.path.join(ACC, "tb", "tb_pq_rsa.v"), os.path.join(ACC, "rtl_pq", "bn_engine.v")], check=True)
print(subprocess.run(["vvp", f"{sd}/rsa_sign.vvp"], cwd=sd, capture_output=True, text=True).stdout.strip().splitlines()[-1])
txm = [int(l, 16) for l in open(f"{sd}/tx_out.hex").read().splitlines() if l and not l.startswith("//")]
got = bytes(txm[:256]); print("rtl==oracle", got == oracle)

tr = open(f"{sd}/trace.txt").read().split("\n")
for k, o in enumerate(ops):
    for r in range(16):
        line = tr[20 * k + r]
        if not (r == o[1] or (o[0] in ("RMULF", "RADD2") and r == o[2])) or o[0] in ("RMSEL", "RLDB") and False: continue
        if o[0] in ("RMSEL", "RSTB"): continue
        v = None if "x" in line else int(line, 16)
        if v != trace[k][r]:
            print("first mismatch at op", k, o, "reg", r, "rtl", line[:16], "exp", f"{trace[k][r]:0256x}"[:16]); sys.exit(1)
print("trace OK")
