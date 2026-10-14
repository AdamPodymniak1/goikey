#!/usr/bin/env python3
"""Bit-exact ML-DSA model (FIPS 204 as in PQClean) built from the primitive operations the FPGA engine implements.

Every `op_*` function operates on a 256-entry list of Python ints with the exact int32 semantics of the C reference,
so the same functions serve as the oracle for the RTL units and as the interpreter backend for the microprograms.
"""
import hashlib, re, os, sys
Q = 8380417; QINV = 58728449; N = 256; D = 13
HERE = os.path.dirname(os.path.abspath(__file__))
_src = open(os.path.join(HERE, "..", "..", "..", "..", "lib", "ML-DSA65", "ntt.c")).read()
ZETAS = [int(x) for x in re.findall(r"-?\d+", _src[_src.index("zetas[N] = {") + 12:_src.index("};")])]
assert len(ZETAS) == 256 and ZETAS[1] == 25847

PARAMS = {
    44: dict(K=4, L=4, ETA=2, TAU=39, BETA=78, G1BITS=17, G2DIV=88, OMEGA=80, CT=32),
    65: dict(K=6, L=5, ETA=4, TAU=49, BETA=196, G1BITS=19, G2DIV=32, OMEGA=55, CT=48),
    87: dict(K=8, L=7, ETA=2, TAU=60, BETA=120, G1BITS=19, G2DIV=32, OMEGA=75, CT=64),
}
def s32(x): x &= 0xFFFFFFFF; return x - (1 << 32) if x & 0x80000000 else x
def s64(x): x &= (1 << 64) - 1; return x - (1 << 64) if x >> 63 else x

def montgomery_reduce(a):
    t = s32((a & 0xFFFFFFFFFFFFFFFF) * QINV)           # (int32)((uint64)a * QINV)
    return s32((a - t * Q) >> 32)
def reduce32(a): t = (a + (1 << 22)) >> 23; return s32(a - t * Q)
def caddq(a): return s32(a + (Q if a < 0 else 0))

def op_ntt(a):
    a = list(a); k = 0; ln = 128
    while ln > 0:
        for start in range(0, N, 2 * ln):
            k += 1; zeta = ZETAS[k]
            for j in range(start, start + ln):
                t = montgomery_reduce(zeta * a[j + ln])
                a[j + ln] = s32(a[j] - t); a[j] = s32(a[j] + t)
        ln >>= 1
    return a
def op_intt(a):
    a = list(a); k = 256; ln = 1
    while ln < N:
        for start in range(0, N, 2 * ln):
            k -= 1; zeta = -ZETAS[k]
            for j in range(start, start + ln):
                t = a[j]; a[j] = s32(t + a[j + ln]); a[j + ln] = s32(t - a[j + ln])
                a[j + ln] = montgomery_reduce(zeta * a[j + ln])
        ln <<= 1
    return [montgomery_reduce(41978 * x) for x in a]
def op_pmul(a, b): return [montgomery_reduce(x * y) for x, y in zip(a, b)]
def op_add(a, b): return [s32(x + y) for x, y in zip(a, b)]
def op_sub(a, b): return [s32(x - y) for x, y in zip(a, b)]
def op_reduce(a): return [reduce32(x) for x in a]
def op_caddq(a): return [caddq(x) for x in a]
def op_power2round(a):
    a1 = [(x + (1 << (D - 1)) - 1) >> D for x in a]
    return a1, [s32(x - (y << D)) for x, y in zip(a, a1)]
def decompose1(a, g2div):
    g2 = (Q - 1) // g2div
    a1 = (a + 127) >> 7
    if g2div == 32: a1 = ((a1 * 1025 + (1 << 21)) >> 22) & 15
    else:
        a1 = (a1 * 11275 + (1 << 23)) >> 24
        a1 ^= ((43 - a1) >> 31) & a1
    a0 = a - a1 * 2 * g2
    a0 -= (((Q - 1) // 2 - a0) >> 31) & Q
    return a1, a0
def op_decompose(a, g2div):
    r = [decompose1(x, g2div) for x in a]
    return [x[0] for x in r], [x[1] for x in r]
def op_make_hint(w0, w1, g2div):
    g2 = (Q - 1) // g2div
    h = [1 if (a0 > g2 or a0 < -g2 or (a0 == -g2 and a1 != 0)) else 0 for a0, a1 in zip(w0, w1)]
    return h, sum(h)
def op_use_hint(a, h, g2div):
    out = []
    for x, hh in zip(a, h):
        a1, a0 = decompose1(x, g2div)
        if hh == 0: out.append(a1)
        elif g2div == 32: out.append((a1 + 1) & 15 if a0 > 0 else (a1 - 1) & 15)
        else:
            if a0 > 0: out.append(0 if a1 == 43 else a1 + 1)
            else: out.append(43 if a1 == 0 else a1 - 1)
    return out
def op_chknorm(a, B):
    if B > (Q - 1) // 8: return 1
    for x in a:
        t = x >> 31; t = s32(x - (t & s32(2 * x)))
        if t >= B: return 1
    return 0

# ---------------- samplers (byte-stream consumers) ----------------
class Stream:
    """Incremental SHAKE: absorb, then squeeze byte by byte."""
    def __init__(self, bits):
        self.h = hashlib.shake_128() if bits == 128 else hashlib.shake_256(); self.buf = b""; self.pos = 0; self.fin = False
    def absorb(self, d): assert not self.fin; self.h.update(d)
    def take(self, n):
        self.fin = True
        need = self.pos + n
        if len(self.buf) < need: self.buf = self.h.digest(max(need, 2 * len(self.buf), 512))
        r = self.buf[self.pos:self.pos + n]; self.pos += n; return r
def op_sample_uniform(st):
    a = []
    while len(a) < N:
        b = st.take(3); t = (b[0] | b[1] << 8 | b[2] << 16) & 0x7FFFFF
        if t < Q: a.append(t)
    return a
def op_sample_eta(st, eta):
    a = []
    while len(a) < N:
        b = st.take(1)[0]; t0, t1 = b & 15, b >> 4
        for t in (t0, t1):
            if len(a) >= N: break
            if eta == 2:
                if t < 15: a.append(2 - (t - (205 * t >> 10) * 5))
            else:
                if t < 9: a.append(4 - t)
    return a
def unpack_bits(data, nbits, count):
    v = int.from_bytes(data, "little"); m = (1 << nbits) - 1
    return [(v >> (nbits * i)) & m for i in range(count)]
def pack_bits(vals, nbits):
    v = 0
    for i, x in enumerate(vals): v |= (x & ((1 << nbits) - 1)) << (nbits * i)
    return v.to_bytes(len(vals) * nbits // 8, "little")
def op_sample_gamma1(st, g1bits):
    nb = g1bits + 1; raw = st.take(N * nb // 8)
    return [(1 << g1bits) - x for x in unpack_bits(raw, nb, N)]
def op_sample_ball(st, tau):
    buf = st.take(8); signs = int.from_bytes(buf, "little")
    c = [0] * N
    for i in range(N - tau, N):
        while True:
            b = st.take(1)[0]
            if b <= i: break
        c[i] = c[b]; c[b] = 1 - 2 * (signs & 1); signs >>= 1
    return c

# ---------------- packers ----------------
def pk_t1(a): return pack_bits(a, 10)
def pk_t0(a): return pack_bits([(1 << (D - 1)) - x for x in a], 13)
def upk_t0(b): return [(1 << (D - 1)) - x for x in unpack_bits(b, 13, N)]
def pk_eta(a, eta): nb = 3 if eta == 2 else 4; return pack_bits([eta - x for x in a], nb)
def upk_eta(b, eta): nb = 3 if eta == 2 else 4; return [eta - x for x in unpack_bits(b, nb, N)]
def pk_z(a, g1bits): return pack_bits([(1 << g1bits) - x for x in a], g1bits + 1)
def pk_w1(a, g2div): return pack_bits(a, 6 if g2div == 88 else 4)
def upk_w1(b, g2div): return unpack_bits(b, 6 if g2div == 88 else 4, N)

def expand_a(rho, P, i, j):
    st = Stream(128); st.absorb(rho + bytes([j, i])); return op_sample_uniform(st)
def shake256(data, n): return hashlib.shake_256(data).digest(n)

def keygen(ps, seed):
    p = PARAMS[ps]; K, L, ETA = p["K"], p["L"], p["ETA"]
    buf = shake256(seed + bytes([K, L]), 128); rho, rhoprime, key = buf[:32], buf[32:96], buf[96:128]
    s1, s2 = [], []
    for i in range(L):
        st = Stream(256); st.absorb(rhoprime + bytes([i, 0])); s1.append(op_sample_eta(st, ETA))
    for i in range(K):
        st = Stream(256); st.absorb(rhoprime + bytes([L + i, 0])); s2.append(op_sample_eta(st, ETA))
    s1h = [op_ntt(x) for x in s1]
    t1, t0 = [], []
    for i in range(K):
        acc = None
        for j in range(L):
            m = op_pmul(expand_a(rho, p, i, j), s1h[j]); acc = m if acc is None else op_add(acc, m)
        acc = op_intt(op_reduce(acc)); acc = op_caddq(op_add(acc, s2[i]))
        a1, a0 = op_power2round(acc); t1.append(a1); t0.append(a0)
    pk = rho + b"".join(pk_t1(x) for x in t1)
    tr = shake256(pk, 64)
    sk = rho + key + tr + b"".join(pk_eta(x, ETA) for x in s1) + b"".join(pk_eta(x, ETA) for x in s2) + b"".join(pk_t0(x) for x in t0)
    return pk, sk

def sign(ps, sk, msg, rnd):
    p = PARAMS[ps]; K, L, ETA, TAU, BETA = p["K"], p["L"], p["ETA"], p["TAU"], p["BETA"]
    G1, G2D, OMEGA, CT = p["G1BITS"], p["G2DIV"], p["OMEGA"], p["CT"]
    G1V = 1 << G1; G2 = (Q - 1) // G2D
    eb = 96 if ETA == 2 else 128; t0b = 416
    rho, key, tr = sk[:32], sk[32:64], sk[64:128]; o = 128
    s1 = [upk_eta(sk[o + i * eb:o + (i + 1) * eb], ETA) for i in range(L)]; o += L * eb
    s2 = [upk_eta(sk[o + i * eb:o + (i + 1) * eb], ETA) for i in range(K)]; o += K * eb
    t0 = [upk_t0(sk[o + i * t0b:o + (i + 1) * t0b]) for i in range(K)]
    mu = shake256(tr + bytes([0, 0]) + msg, 64)
    rhoprime = shake256(key + rnd + mu, 64)
    s1h = [op_ntt(x) for x in s1]; s2h = [op_ntt(x) for x in s2]; t0h = [op_ntt(x) for x in t0]
    nonce = 0
    while True:
        y = []
        for j in range(L):
            st = Stream(256); st.absorb(rhoprime + (L * nonce + j).to_bytes(2, "little")); y.append(op_sample_gamma1(st, G1))
        nonce += 1
        yh = [op_ntt(x) for x in y]
        w = []
        for i in range(K):
            acc = None
            for j in range(L):
                m = op_pmul(expand_a(rho, p, i, j), yh[j]); acc = m if acc is None else op_add(acc, m)
            w.append(op_caddq(op_intt(op_reduce(acc))))
        w1, w0 = [], []
        for i in range(K):
            a1, a0 = op_decompose(w[i], G2D); w1.append(a1); w0.append(a0)
        w1p = b"".join(pk_w1(x, G2D) for x in w1)
        ctilde = shake256(mu + w1p, CT)
        st = Stream(256); st.absorb(ctilde); ch = op_ntt(op_sample_ball(st, TAU))
        z = []; bad = 0
        for j in range(L):
            zj = op_intt(op_pmul(ch, s1h[j])); zj = op_reduce(op_add(zj, y[j])); z.append(zj)
            bad |= op_chknorm(zj, (1 << G1) - BETA)
        if bad: continue
        h = [None] * K
        for i in range(K):
            hi = op_intt(op_pmul(ch, s2h[i])); w0[i] = op_reduce(op_sub(w0[i], hi)); bad |= op_chknorm(w0[i], G2 - BETA)
        if bad: continue
        hint = []; n = 0
        for i in range(K):
            hi = op_reduce(op_intt(op_pmul(ch, t0h[i]))); bad |= op_chknorm(hi, G2)
            w0[i] = op_add(w0[i], hi); hh, c = op_make_hint(w0[i], w1[i], G2D); hint.append(hh); n += c
        if bad or n > OMEGA: continue
        sig = ctilde + b"".join(pk_z(x, G1) for x in z)
        hb = bytearray(OMEGA + K); k = 0
        for i in range(K):
            for j in range(N):
                if hint[i][j]: hb[k] = j; k += 1
            hb[OMEGA + i] = k
        return sig + bytes(hb)

class CRng:                                   # replicates hw/accel/ref/pq/rng_stub.c
    def __init__(self, seed): self.st = seed or 0x9E3779B97F4A7C15
    def read(self, n):
        out = bytearray(); M = (1 << 64) - 1
        for _ in range(n):
            self.st ^= self.st >> 12; self.st ^= (self.st << 25) & M; self.st ^= self.st >> 27
            out.append(((self.st * 0x2545F4914F6CDD1D) & M) >> 56)
        return bytes(out)

if __name__ == "__main__":
    import subprocess
    msg = bytes.fromhex("48656c6c6f")
    for ps in (44, 65, 87):
        out = subprocess.run([os.path.join(HERE, "golden"), str(ps), "7", msg.hex()], capture_output=True, text=True).stdout
        g = dict(l.split("=") for l in out.split())
        rng = CRng(7); seed = rng.read(32); pk, sk = keygen(ps, seed); rnd = rng.read(32)
        assert pk.hex() == g["pk"], f"pk mismatch {ps}"; assert sk.hex() == g["sk"], f"sk mismatch {ps}"
        sig = sign(ps, sk, msg, rnd)
        assert sig.hex() == g["sig"], f"sig mismatch {ps}"
        print(f"ML-DSA-{ps}: keygen + sign identical to the C reference (pk {len(pk)}, sk {len(sk)}, sig {len(sig)} bytes)")
