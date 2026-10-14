#!/usr/bin/env python3
"""Single-operation diagnostics of the ML-DSA engine on the board (needs a bitstream built with PQ_DEBUG=1)."""
import os, sys, struct
sys.path.insert(0, os.path.dirname(__file__)); sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "ref", "pq"))
from tro_accel import PqAccel
import pq_model as M
a = PqAccel(sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1", 1500000, timeout=30)
rho = bytes(range(1, 33))
def uni(j, i): st = M.Stream(128); st.absorb(rho + bytes([j, i])); return M.op_sample_uniform(st)
def dump(cmd):
    r = a.call(cmd, rho); return [x if x < 1 << 31 else x - (1 << 32) for x in struct.unpack("<256I", r)]
def report(name, got, exp):
    bad = [i for i in range(256) if got[i] != exp[i]]
    print(f"[{'PASS' if not bad else 'FAIL'}] {name}" + ("" if not bad else f": {len(bad)} / 256 differ, first at {bad[0]}: got {got[bad[0]]} expected {exp[bad[0]]}"))
    return not bad
A = uni(0, 0); B = uni(0, 1)
ok = report("uniform sampler", dump(0x78), A)
ok &= report("NTT of a uniform poly", dump(0x79), M.op_ntt(A))
ok &= report("pointwise Montgomery product", dump(0x7A), M.op_pmul(A, B))
ok &= report("inverse NTT", dump(0x7B), M.op_intt(A))
st = M.Stream(256); st.absorb(rho + rho + bytes([0, 0])); ok &= report("eta=2 sampler", dump(0x7C), M.op_sample_eta(st, 2))
chain = M.op_caddq(M.op_intt(M.op_reduce(M.op_pmul(M.op_ntt(A), B))))
ok &= report("NTT -> pmul -> reduce -> INTT -> caddq", dump(0x7D), chain)

# ---- keygen row 0 of ML-DSA-44, stage by stage ----
if len(sys.argv) > 2 or True:
    seed = bytes(range(10, 42))
    r = a.call(0x7E, seed)
    stages = [[(x if x < 1 << 31 else x - (1 << 32)) for x in struct.unpack("<256I", r[1024 * k:1024 * (k + 1)])] for k in range(7)]
    buf = M.shake256(seed + bytes([4, 4]), 128); r_, rp = buf[:32], buf[32:96]
    def S(i, nonce):
        st = M.Stream(256); st.absorb(rp + bytes([nonce, 0])); return M.op_sample_eta(st, 2)
    s1h = [M.op_ntt(S(0, j)) for j in range(4)]
    acc = None
    for j in range(4):
        st = M.Stream(128); st.absorb(r_ + bytes([j, 0])); m = M.op_pmul(M.op_sample_uniform(st), s1h[j]); acc = m if acc is None else M.op_add(acc, m)
    exp = [acc]; red = M.op_reduce(acc); exp.append(red); iv = M.op_intt(red); exp.append(iv)
    s2 = S(0, 4); exp.append(s2); ad = M.op_add(iv, s2); exp.append(ad)
    cq = M.op_caddq(ad); t1, t0 = M.op_power2round(cq); exp += [t1, t0]
    names = ["after A*s1 accumulation", "after reduce32", "after inverse NTT", "s2 sample", "after + s2", "t1 (power2round)", "t0 (power2round)"]
    for n, g, e in zip(names, stages, exp): report("keygen row0: " + n, g, e)

sys.exit(0 if ok else 1)
