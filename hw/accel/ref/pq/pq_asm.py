#!/usr/bin/env python3
"""Assembler, reference interpreter and programs (keygen / sign) for the ML-DSA microcode engine.

Instruction word: [31:24] op | [23:18] a | [17:12] b | [11:6] c | [5:0] d, followed by `imm` 32-bit words.
Ops >= 0x80 carry immediates (count per op in IMMN).  Byte "spaces": 0 RX, 1 TX, 2 SC (scratch), 3 SHAKE-absorb sink.
imm descriptor: [31:30] space | [29:17] offset (13 b) | [16:4] length (13 b).
"""
import hashlib, os, sys
sys.path.insert(0, os.path.dirname(os.path.abspath(__file__)))
import pq_model as M
from rsa_model import SMALL_PRIMES

OPS = dict(NOP=0x00, PNTT=0x02, PINTT=0x03, PMUL=0x04, PMULA=0x05, PADD=0x06, PSUB=0x07, PRED=0x08, PCADDQ=0x09,
           PCLR=0x0A, PCOPY=0x0B, P2R=0x0C, PDEC=0x0D, MKHINT=0x0E, SMPU=0x0F, SMPE=0x10, SMPG=0x11, SMPB=0x12,
           SHINIT=0x13, SHFIN=0x14, SHABSM=0x15, HCLR=0x16, NZCLR=0x17, NZINC=0x18, NOTF=0x1A, SETF0=0x1B, SETF1=0x1C,
           XSET0=0x1D, XSET1=0x1E,
           PARAM=0x80, SHABSB=0x81, SHABSI=0x82, SHABSNZ=0x83, SHSQB=0x84, SHXORKS=0x85, BCMP=0x86, BCPY=0x87,
           RNGB=0x88, CHKN=0x89, PKT1=0x8A, PKT0=0x8B, PKETA=0x8C, PKZ=0x8D, PKW1=0x8E, PKH=0x8F, UPKETA=0x90,
           UPKT0=0x91, ZFILL=0x92, JMP=0x93, JF=0x94, JNF=0x95, FIN=0x96, CHKLEN=0x97, CHKLT=0x98, HCHK=0x99,
           SHABSRX=0x9A, WUID=0x9B, WIMM=0x9C, JXF=0x9D, PDUMP=0x9E,
           # ---- RSA big-number unit (1024-bit registers r0..r15; see pq_rsa.v) ----
           RLDB=0xA0, RSTB=0xA1, RRNG=0xA2, RSETI=0xA3, RMOV=0xA4, RMSEL=0xA5, RR2=0xA6, RMUL=0xA7, RADDM=0xA8, RSUBM=0xA9,
           REXP=0xAA, RSIEVE=0xAB, RREM1=0xAC, RCMP=0xAD, REQ=0xAE, RISZ=0xAF, RSUBI=0xB0, RSHR1=0xB1, RMULF=0xB2, RMASK=0xB3,
           RKINV=0xB4, RDP=0xB5, RSUB=0xB6, RADD2=0xB7, RCSUB=0xB8, UPKW1=0xB9, BFILL=0x9F)
IMMN = {n: 1 for n, v in OPS.items() if v >= 0x80}
IMMN["BCMP"] = 2; IMMN["BCPY"] = 2; IMMN["WIMM"] = 2; IMMN["BFILL"] = 2
for _n in ("RMSEL", "RR2", "RMUL", "RADDM", "RSUBM", "REXP", "RSIEVE", "RCMP", "REQ", "RISZ", "RSHR1", "RMULF", "RMASK", "RSUB", "RADD2", "RCSUB", "RMOV", "RRNG"): IMMN[_n] = 0
RX, TX, SC, SK = 0, 1, 2, 3
def desc(space, off, ln=0): return (space << 30) | (off << 17) | (ln << 4)

class Asm:
    def __init__(self, base=0): self.w = []; self.labels = {}; self.fix = []; self.base = base
    def label(self, n): self.labels[n] = len(self.w)
    def op(self, name, a=0, b=0, c=0, d=0, *imm):
        assert len(imm) == IMMN.get(name, 0), (name, imm)
        self.w.append((OPS[name] << 24) | (a << 18) | (b << 12) | (c << 6) | d)
        self.w.extend(i & 0xFFFFFFFF for i in imm)
    def jump(self, name, label):
        self.w.append(OPS[name] << 24); self.fix.append(len(self.w)); self.w.append(0); self.lab_ref = getattr(self, "lab_ref", {}); self.lab_ref[len(self.w) - 1] = label
    def link(self):
        for pos, lab in (self.lab_ref.items() if hasattr(self, "lab_ref") else []): self.w[pos] = self.base + self.labels[lab]
        return self.w

# ---------------- reference interpreter ----------------
class Dev:
    def __init__(self, payload=b"", master=bytes(range(32)), trng=None):
        self.rx = bytearray(8192); self.rx[:len(payload)] = payload; self.plen = len(payload)
        self.tx = bytearray(8192); self.sc = bytearray(2048); self.master = master
        self.trng = trng or (lambda n: bytes(n)); self.fin = None; self.uid = bytes(range(0xA0, 0xB0))
    def mem(self, space): return (self.rx, self.tx, self.sc)[space]

def run(code, pc, dev, maxsteps=10**9):
    pm = {}                                   # slot -> list of 256 ints
    G = lambda s: pm.setdefault(s, [0] * 256)
    st = None; flag = 0; hcnt = 0; hk = 0; nz = 0; xf = 0
    if not hasattr(dev, 'big'): dev.big = [0] * 16; dev.modn = 1; dev.flagtrace = []
    big = dev.big; M1024 = (1 << 1024) - 1; R1024 = 1 << 1024
    P = dict(eta=2, g1=17, g2=88, tau=39, L=4, omega=80)
    steps = 0
    def sh(): nonlocal st; return st
    while steps < maxsteps:
        steps += 1
        w = code[pc]; op = w >> 24; a = (w >> 18) & 63; b = (w >> 12) & 63; c = (w >> 6) & 63; d = w & 63
        name = REV[op]; n = IMMN.get(name, 0); imm = code[pc + 1:pc + 1 + n]; pc += 1 + n
        def D(x): return ((x >> 30) & 3, (x >> 17) & 0x1FFF, (x >> 4) & 0x1FFF)
        if name == "NOP": pass
        elif name == "PNTT": pm[a] = M.op_ntt(G(a))
        elif name == "PINTT": pm[a] = M.op_intt(G(a))
        elif name == "PMUL": pm[a] = M.op_pmul(G(b), G(c))
        elif name == "PMULA": pm[a] = M.op_add(G(a), M.op_pmul(G(b), G(c)))
        elif name == "PADD": pm[a] = M.op_add(G(b), G(c))
        elif name == "PSUB": pm[a] = M.op_sub(G(b), G(c))
        elif name == "PRED": pm[a] = M.op_reduce(G(a))
        elif name == "PCADDQ": pm[a] = M.op_caddq(G(a))
        elif name == "PCLR": pm[a] = [0] * 256
        elif name == "PCOPY": pm[a] = list(G(b))
        elif name == "P2R": src = G(c); pm[a], pm[b] = M.op_power2round(src)
        elif name == "PDEC": src = G(c); pm[a], pm[b] = M.op_decompose(src, P["g2"])
        elif name == "MKHINT": h, cnt = M.op_make_hint(G(b), G(c), P["g2"]); pm[a] = h; hcnt += cnt
        elif name == "SMPU": pm[a] = M.op_sample_uniform(st)
        elif name == "SMPE": pm[a] = M.op_sample_eta(st, P["eta"])
        elif name == "SMPG": pm[a] = M.op_sample_gamma1(st, P["g1"])
        elif name == "SMPB": pm[a] = M.op_sample_ball(st, P["tau"])
        elif name == "SHINIT": st = M.Stream(128 if a == 0 else 256)
        elif name == "SHFIN": st.fin = True
        elif name == "SHABSM": st.absorb(dev.master)
        elif name == "HCLR": hcnt = 0; hk = 0
        elif name == "NZCLR": nz = 0
        elif name == "NZINC": nz += P["L"]
        elif name == "NOTF": flag ^= 1
        elif name == "SETF0": flag = 0
        elif name == "SETF1": flag = 1
        elif name == "XSET0": xf = 0
        elif name == "XSET1": xf = 1
        elif name == "JXF":
            if xf: pc = imm[0]
        elif name == "WUID": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + 16] = dev.uid
        elif name == "WIMM": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + 2] = (imm[1] & 0xFFFF).to_bytes(2, "big")
        elif name == "PARAM":
            P["eta"] = 2 if a == 0 else 4; P["g1"] = 17 if b == 0 else 19; P["g2"] = 88 if c == 0 else 32
            P["tau"] = imm[0] & 255; P["L"] = (imm[0] >> 8) & 255; P["omega"] = (imm[0] >> 16) & 255
        elif name == "SHABSB": sp, off, ln = D(imm[0]); st.absorb(bytes(dev.mem(sp)[off:off + ln]))
        elif name == "SHABSRX": st.absorb(bytes(dev.rx[imm[0] & 0x1FFF:dev.plen]))
        elif name == "SHABSI": st.absorb(bytes([imm[0] & 255]))
        elif name == "SHABSNZ": st.absorb(((nz + imm[0]) & 0xFFFF).to_bytes(2, "little"))
        elif name == "SHSQB": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + ln] = st.take(ln)
        elif name == "SHXORKS":
            sp, off, ln = D(imm[0]); ks = st.take(ln); m = dev.mem(sp)
            for i in range(ln): m[off + i] ^= ks[i]
        elif name == "BCMP":
            s1, o1, l1 = D(imm[0]); s2, o2, _ = D(imm[1])
            flag |= int(bytes(dev.mem(s1)[o1:o1 + l1]) != bytes(dev.mem(s2)[o2:o2 + l1]))
        elif name == "BCPY":
            s1, o1, l1 = D(imm[0]); s2, o2, _ = D(imm[1]); dev.mem(s1)[o1:o1 + l1] = bytes(dev.mem(s2)[o2:o2 + l1])
        elif name == "RNGB": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + ln] = dev.trng(ln)
        elif name == "CHKN": flag |= M.op_chknorm(G(a), imm[0])
        elif name in ("PKT1", "PKT0", "PKETA", "PKZ", "PKW1"):
            sp, off, _ = D(imm[0]); x = G(a)
            data = {"PKT1": lambda: M.pk_t1(x), "PKT0": lambda: M.pk_t0(x), "PKETA": lambda: M.pk_eta(x, P["eta"]),
                    "PKZ": lambda: M.pk_z(x, P["g1"]), "PKW1": lambda: M.pk_w1(x, P["g2"])}[name]()
            if sp == 3: st.absorb(data)
            else: dev.mem(sp)[off:off + len(data)] = data
        elif name == "PKH":
            sp, off, _ = D(imm[0]); m = dev.mem(sp); h = G(a)
            for j in range(256):
                if h[j]:
                    if hk < P["omega"]: m[off + hk] = j
                    hk += 1
            if hk > P["omega"]: flag |= 1
            m[off + P["omega"] + b] = hk & 255
        elif name == "BFILL": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + ln] = bytes([imm[1] & 255]) * ln
        elif name == "RLDB": sp, off, ln = D(imm[0]); big[a] = int.from_bytes(bytes(dev.mem(sp)[off:off + ln]), "big")
        elif name == "RSTB": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + ln] = (big[a] & ((1 << (8 * ln)) - 1)).to_bytes(ln, "big")
        elif name == "RRNG": big[a] = int.from_bytes(dev.trng(128), "big")
        elif name == "RSETI": big[a] = imm[0]
        elif name == "RMOV": big[a] = big[b]
        elif name == "RMSEL": dev.modn = big[a]
        elif name == "RR2": big[a] = (R1024 * R1024) % dev.modn
        elif name == "RMUL": big[a] = big[b] * big[c] * pow(R1024, -1, dev.modn) % dev.modn
        elif name == "RADDM":
            s_ = big[b] + big[c]; big[a] = s_ - dev.modn if s_ >= dev.modn else s_
        elif name == "RSUBM":
            s_ = big[b] - big[c]; big[a] = s_ + dev.modn if s_ < 0 else s_
        elif name == "REXP":
            base = big[b] * pow(R1024, -1, dev.modn) % dev.modn; big[a] = pow(base, big[c], dev.modn) * R1024 % dev.modn
        elif name == "RSIEVE": flag = int(any(big[a] % q_ == 0 for q_ in SMALL_PRIMES)); dev.flagtrace.append(flag)
        elif name == "RREM1": flag = int(big[a] % imm[0] == 1); dev.flagtrace.append(flag)
        elif name == "RCMP": flag = int(big[a] < big[b])
        elif name == "REQ": flag = int(big[a] == big[b]); dev.flagtrace.append(flag)
        elif name == "RISZ": flag = int(big[a] == 0)
        elif name == "RSUBI": big[a] = (big[b] - imm[0]) & M1024
        elif name == "RSHR1": big[a] = big[b] >> 1
        elif name == "RMULF": x_ = big[c] * big[d]; big[a] = x_ & M1024; big[b] = x_ >> 1024
        elif name == "RMASK": big[a] |= (3 << 1022) | 3
        elif name == "RKINV": e_ = imm[0]; big[a] = (e_ - pow(big[b] % e_, -1, e_)) % e_
        elif name == "RDP":
            e_ = imm[0]; t_ = 1 + big[c] * big[b]; assert t_ % e_ == 0; big[a] = t_ // e_
        elif name == "RSUB": big[a] = (big[b] - big[c]) & M1024
        elif name == "RADD2": x_ = (big[b] << 1024) + big[a] + big[c]; big[a] = x_ & M1024; big[b] = (x_ >> 1024) & M1024
        elif name == "RCSUB": big[a] = big[b] - dev.modn if big[b] >= dev.modn else big[b]
        elif name == "PDUMP":
            sp, off, _ = D(imm[0]); dev.mem(sp)[off:off + 1024] = b"".join((x & 0xFFFFFFFF).to_bytes(4, "little") for x in G(a))
        elif name == "UPKETA":
            sp, off, _ = D(imm[0]); eb = 96 if P["eta"] == 2 else 128
            pm[a] = M.upk_eta(bytes(dev.mem(sp)[off:off + eb]), P["eta"])
        elif name == "UPKW1": sp, off, _ = D(imm[0]); pm[a] = M.upk_w1(bytes(dev.mem(sp)[off:off + (192 if P["g2"] == 88 else 128)]), P["g2"])
        elif name == "UPKT0": sp, off, _ = D(imm[0]); pm[a] = M.upk_t0(bytes(dev.mem(sp)[off:off + 416]))
        elif name == "ZFILL": sp, off, ln = D(imm[0]); dev.mem(sp)[off:off + ln] = bytes(ln)
        elif name == "JMP": pc = imm[0]
        elif name == "JF":
            if flag: pc = imm[0]
        elif name == "JNF":
            if not flag: pc = imm[0]
        elif name == "FIN": dev.fin = (a, imm[0] & 0xFFFF); return steps
        elif name == "CHKLEN": flag = int(dev.plen != imm[0])
        elif name == "CHKLT": flag = int(dev.plen < imm[0])
        elif name == "HCHK": flag |= int(hk > imm[0])
        else: raise ValueError(name)
    raise RuntimeError("step limit")
REV = {v: k for k, v in OPS.items()}

# ---------------- programs ----------------
SC_SEED = 0       # keygen: rho 0..31, rhoprime 32..95, key 96..127   | sign: rho(0) tr(32+?) ... see below
# scratch layout (bytes)
SC_RHO, SC_RHOP, SC_KEY, SC_SEEDIN = 0, 32, 96, 128        # keygen: SHAKE(seed|K|L) -> [0:128); raw seed at 128
SC_MU, SC_RNDS, SC_RHOPRIME, SC_CT, SC_TAGC, SC_W1 = 128, 192, 224, 288, 352, 512  # sign (+ rho copy at 0)
def sizes(ps):
    p = M.PARAMS[ps]; K, L, ETA = p["K"], p["L"], p["ETA"]
    eb = 96 if ETA == 2 else 128
    zb = 576 if p["G1BITS"] == 17 else 640; wb = 192 if p["G2DIV"] == 88 else 128
    sk = 128 + (L + K) * eb + K * 416; pk = 32 + K * 320; sig = p["CT"] + L * zb + p["OMEGA"] + K
    return dict(p, eb=eb, zb=zb, wb=wb, sk=sk, pk=pk, sig=sig)

def param(A, ps):
    s = sizes(ps)
    A.op("PARAM", 0 if s["ETA"] == 2 else 1, 0 if s["G1BITS"] == 17 else 1, 0 if s["G2DIV"] == 88 else 1, 0,
         s["TAU"] | (s["L"] << 8) | (s["OMEGA"] << 16))

def wrap_stream(A, nonce_d, init_byte):
    A.op("SHINIT", 1); A.op("SHABSI", 0, 0, 0, 0, init_byte); A.op("SHABSM"); A.op("SHABSB", 0, 0, 0, 0, nonce_d)

def prog_keygen(ps, base=0):
    """TX layout: nonce[16] | sk[sklen] | tag[16] | pk[pklen]. payload (explicit seed): seed[32]."""
    s = sizes(ps); K, L = s["K"], s["L"]; A = Asm(base); A.entries = {}
    A.entries['trng'] = base; A.op('XSET0'); A.jump('JMP', 'kg')
    A.entries['expl'] = base + len(A.w); A.op('XSET1'); A.jump('JMP', 'kg')
    A.label('kg'); param(A, ps)
    SKB = 16; TAGB = 16 + s["sk"]; PKB = TAGB + 16
    A.jump("JXF", "kg_expl")
    A.op("CHKLEN", 0, 0, 0, 0, 0); A.jump("JF", "bad_len"); A.op("RNGB", 0, 0, 0, 0, desc(SC, SC_SEEDIN, 32)); A.jump("JMP", "kg_go")
    A.label("kg_expl"); A.op("CHKLEN", 0, 0, 0, 0, 32); A.jump("JF", "bad_len"); A.op("BCPY", 0, 0, 0, 0, desc(SC, SC_SEEDIN, 32), desc(RX, 0))
    A.label("kg_go")
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_SEEDIN, 32)); A.op("SHABSI", 0, 0, 0, 0, K); A.op("SHABSI", 0, 0, 0, 0, L)
    A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, 0, 128))
    A.op("BCPY", 0, 0, 0, 0, desc(TX, SKB, 32), desc(SC, SC_RHO)); A.op("BCPY", 0, 0, 0, 0, desc(TX, SKB + 32, 32), desc(SC, SC_KEY))
    A.op("BCPY", 0, 0, 0, 0, desc(TX, PKB, 32), desc(SC, SC_RHO))
    S1H = 0; T0, T1, T2, T3, TA = L, L + 1, L + 2, L + 3, L + 4
    for j in range(L):                                       # s1
        A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHOP, 64)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, 0)
        A.op("SHFIN"); A.op("SMPE", S1H + j); A.op("PKETA", S1H + j, 0, 0, 0, desc(TX, SKB + 128 + j * s["eb"])); A.op("PNTT", S1H + j)
    for i in range(K):
        for j in range(L):
            A.op("SHINIT", 0); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHO, 32)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, i)
            A.op("SHFIN"); A.op("SMPU", TA); A.op("PMUL" if j == 0 else "PMULA", T0, TA, S1H + j)
        A.op("PRED", T0); A.op("PINTT", T0)
        A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHOP, 64)); A.op("SHABSI", 0, 0, 0, 0, L + i); A.op("SHABSI", 0, 0, 0, 0, 0)
        A.op("SHFIN"); A.op("SMPE", T1); A.op("PKETA", T1, 0, 0, 0, desc(TX, SKB + 128 + (L + i) * s["eb"]))
        A.op("PADD", T0, T0, T1); A.op("PCADDQ", T0); A.op("P2R", T2, T3, T0)
        A.op("PKT1", T2, 0, 0, 0, desc(TX, PKB + 32 + i * 320)); A.op("PKT0", T3, 0, 0, 0, desc(TX, SKB + 128 + (L + K) * s["eb"] + i * 416))
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(TX, PKB, s["pk"])); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(TX, SKB + 64, 64))   # tr
    A.op("RNGB", 0, 0, 0, 0, desc(TX, 0, 16))                                     # wrap: nonce
    wrap_stream(A, desc(TX, 0, 16), 0x45); A.op("SHFIN"); A.op("SHXORKS", 0, 0, 0, 0, desc(TX, SKB, s["sk"]))
    wrap_stream(A, desc(TX, 0, 16), 0x4D); A.op("SHABSB", 0, 0, 0, 0, desc(TX, SKB, s["sk"])); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(TX, TAGB, 16))
    A.op("FIN", 0, 0, 0, 0, PKB + s["pk"])
    A.label("bad_len"); A.op("FIN", 2, 0, 0, 0, 0)
    A.code = A.link(); return A

def prog_sign(ps, base=0):
    """payload: blob[16+sk+16] | (rnd[32]) | msg.  Response: signature."""
    s = sizes(ps); K, L = s["K"], s["L"]; A = Asm(base); A.entries = {}
    A.entries['trng'] = base; A.op('XSET0'); A.jump('JMP', 'sg')
    A.entries['expl'] = base + len(A.w); A.op('XSET1'); A.jump('JMP', 'sg')
    A.label('sg'); param(A, ps)
    BL = 32 + s["sk"]; SKB = 16; MSGOFF = BL + 32            # payload: blob | rnd[32] | msg (rnd ignored by the TRNG variant)
    A.op("CHKLT", 0, 0, 0, 0, MSGOFF); A.jump("JF", "bad_len")
    # --- unwrap: verify tag, then decrypt sk in place in RX ---
    wrap_stream(A, desc(RX, 0, 16), 0x4D); A.op("SHABSB", 0, 0, 0, 0, desc(RX, SKB, s["sk"])); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, SC_TAGC, 16))
    A.op("SETF0"); A.op("BCMP", 0, 0, 0, 0, desc(SC, SC_TAGC, 16), desc(RX, SKB + s["sk"])); A.jump("JF", "auth_fail")
    wrap_stream(A, desc(RX, 0, 16), 0x45); A.op("SHFIN"); A.op("SHXORKS", 0, 0, 0, 0, desc(RX, SKB, s["sk"]))
    # sk now at RX[16..]: rho 0, key 32, tr 64, s1, s2, t0
    A.op("BCPY", 0, 0, 0, 0, desc(SC, SC_RHO, 32), desc(RX, SKB))
    A.jump("JXF", "sg_expl"); A.op("RNGB", 0, 0, 0, 0, desc(SC, SC_RNDS, 32)); A.jump("JMP", "sg_go")
    A.label("sg_expl"); A.op("BCPY", 0, 0, 0, 0, desc(SC, SC_RNDS, 32), desc(RX, BL))
    A.label("sg_go")
    # mu = SHAKE256(tr | 0 | 0 | msg)
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(RX, SKB + 64, 64)); A.op("SHABSI", 0, 0, 0, 0, 0); A.op("SHABSI", 0, 0, 0, 0, 0)
    A.op("SHABSRX", 0, 0, 0, 0, MSGOFF); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, SC_MU, 64))
    # rhoprime = SHAKE256(key | rnd | mu)
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(RX, SKB + 32, 32)); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RNDS, 32))
    A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_MU, 64)); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, SC_RHOPRIME, 64))
    Y, YH, W0 = 0, L, 2 * L                                  # w1 is kept packed in SC and unpacked on demand (UPKW1): saves K slots
    CP, TA, TB, TC = 2 * L + K, 2 * L + K + 1, 2 * L + K + 2, 2 * L + K + 3
    A.op("NZCLR")
    A.label("rej")
    for j in range(L):                                       # y = ExpandMask
        A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHOPRIME, 64)); A.op("SHABSNZ", 0, 0, 0, 0, j); A.op("SHFIN")
        A.op("SMPG", Y + j); A.op("PCOPY", YH + j, Y + j); A.op("PNTT", YH + j)
    A.op("NZINC")
    for i in range(K):                                       # w = A*yhat, decompose, pack w1
        for j in range(L):
            A.op("SHINIT", 0); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHO, 32)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, i)
            A.op("SHFIN"); A.op("SMPU", TA); A.op("PMUL" if j == 0 else "PMULA", W0 + i, TA, YH + j)
        A.op("PRED", W0 + i); A.op("PINTT", W0 + i); A.op("PCADDQ", W0 + i); A.op("PDEC", TA, W0 + i, W0 + i)
        A.op("PKW1", TA, 0, 0, 0, desc(SC, SC_W1 + i * s["wb"]))
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_MU, 64)); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_W1, K * s["wb"]))
    A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, SC_CT, s["CT"]))
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_CT, s["CT"])); A.op("SHFIN"); A.op("PCLR", CP); A.op("SMPB", CP); A.op("PNTT", CP)
    A.op("SETF0"); A.op("HCLR")
    for j in range(L):                                       # z = y + c*s1
        A.op("UPKETA", TB, 0, 0, 0, desc(RX, SKB + 128 + j * s["eb"])); A.op("PNTT", TB); A.op("PMUL", TB, CP, TB); A.op("PINTT", TB)
        A.op("PADD", TB, TB, Y + j); A.op("PRED", TB); A.op("CHKN", TB, 0, 0, 0, (1 << s["G1BITS"]) - s["BETA"])
        A.op("PKZ", TB, 0, 0, 0, desc(TX, s["CT"] + j * s["zb"]))
    A.jump("JF", "rej")
    g2 = (M.Q - 1) // s["G2DIV"]
    for i in range(K):                                       # w0 - c*s2
        A.op("UPKETA", TB, 0, 0, 0, desc(RX, SKB + 128 + (L + i) * s["eb"])); A.op("PNTT", TB); A.op("PMUL", TB, CP, TB); A.op("PINTT", TB)
        A.op("PSUB", W0 + i, W0 + i, TB); A.op("PRED", W0 + i); A.op("CHKN", W0 + i, 0, 0, 0, g2 - s["BETA"])
    A.jump("JF", "rej")
    A.op("ZFILL", 0, 0, 0, 0, desc(TX, s["CT"] + L * s["zb"], s["OMEGA"] + K))
    for i in range(K):                                       # c*t0, hints
        A.op("UPKT0", TB, 0, 0, 0, desc(RX, SKB + 128 + (L + K) * s["eb"] + i * 416)); A.op("PNTT", TB); A.op("PMUL", TB, CP, TB)
        A.op("PINTT", TB); A.op("PRED", TB); A.op("CHKN", TB, 0, 0, 0, g2)
        A.op("PADD", W0 + i, W0 + i, TB); A.op("UPKW1", TA, 0, 0, 0, desc(SC, SC_W1 + i * s["wb"])); A.op("MKHINT", TC, W0 + i, TA)
        A.op("PKH", TC, i, 0, 0, desc(TX, s["CT"] + L * s["zb"]))
    A.op("HCHK", 0, 0, 0, 0, s["OMEGA"]); A.jump("JF", "rej")
    A.op("BCPY", 0, 0, 0, 0, desc(TX, 0, s["CT"]), desc(SC, SC_CT))
    A.op("FIN", 0, 0, 0, 0, s["sig"])
    A.label("auth_fail"); A.op("FIN", 4, 0, 0, 0, 0)
    A.label("bad_len"); A.op("FIN", 2, 0, 0, 0, 0)
    A.code = A.link(); return A

def wrap_py(master, sk, nonce):
    ks = hashlib.shake_256(b"E" + master + nonce).digest(len(sk)); ct = bytes(a ^ b for a, b in zip(sk, ks))
    return nonce + ct + hashlib.shake_256(b"M" + master + nonce + ct).digest(16)


# ---------------- RSA-2048 programs ----------------
RSA_BASES = (2, 3, 5, 7, 11)                # Euler/MR bases: p = 3 mod 4 => a^((p-1)/2) must be +-1 mod p
RSA_E = 65537
def prog_rsa(base=0):
    """cmds: gen -> blob(672) | n(256);  pub(blob) -> n;  sign(blob | sha256 digest) -> 256-byte RSASSA-PKCS1-v1_5 signature.
    blob = nonce16 | ct(p|q|dp|dq|qinv, 5*128) | tag16  (SHAKE256 keystream/MAC under MASTER, like ML-DSA)."""
    A = Asm(base); A.entries = {}
    SKB, KB = 16, 640
    def R(name, a=0, b=0, c=0, d=0, *imm): A.op(name, a, b, c, d, *imm)
    # ---------------- keygen ----------------
    A.entries["gen"] = base
    A.op("CHKLEN", 0, 0, 0, 0, 0); A.jump("JF", "bad_len")
    P, Q, E, X, AM, R2, PM1, ONE, NLO, NHI, DX, K, QI = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    def gen_prime(dst, other, lab):
        A.label(lab + "_try")
        R("RRNG", dst); R("RMASK", dst)
        R("RSIEVE", dst)
        # RSIEVE sets flag=1 when divisible by a small prime -> retry
        A.jump("JF", lab + "_try")
        R("RREM1", dst, 0, 0, 0, RSA_E); A.jump("JF", lab + "_try")
        if other is not None:
            R("REQ", dst, other); A.jump("JF", lab + "_try")
        R("RMSEL", dst); R("RR2", R2); R("RSHR1", E, dst); R("RSUBI", PM1, dst, 0, 0, 1)
        R("RSETI", ONE, 0, 0, 0, 1)
        for k, bs in enumerate(RSA_BASES):
            R("RSETI", X, 0, 0, 0, bs); R("RMUL", AM, X, R2); R("REXP", X, AM, E); R("RMUL", X, X, ONE)
            R("REQ", X, ONE); A.jump("JF", f"{lab}_ok{k}")
            R("REQ", X, PM1); A.jump("JF", f"{lab}_ok{k}")
            A.jump("JMP", lab + "_try")
            A.label(f"{lab}_ok{k}")
    gen_prime(P, None, "gp"); gen_prime(Q, P, "gq")
    R("RMULF", NLO, NHI, P, Q)
    A.op("RNGB", 0, 0, 0, 0, desc(TX, 0, 16))
    R("RSTB", P, 0, 0, 0, desc(TX, SKB, 128)); R("RSTB", Q, 0, 0, 0, desc(TX, SKB + 128, 128))
    R("RSTB", NHI, 0, 0, 0, desc(TX, SKB + KB + 16, 128)); R("RSTB", NLO, 0, 0, 0, desc(TX, SKB + KB + 16 + 128, 128))
    for (pp, dd, off) in ((P, DX, 256), (Q, DX, 384)):                 # dp, dq
        R("RSUBI", PM1, pp, 0, 0, 1); R("RKINV", K, PM1, 0, 0, RSA_E); R("RDP", dd, PM1, K, 0, RSA_E)
        R("RSTB", dd, 0, 0, 0, desc(TX, SKB + off, 128))
    R("RMSEL", P); R("RR2", R2); R("RSUBI", E, P, 0, 0, 2); R("RCSUB", X, Q); R("RMUL", AM, X, R2); R("REXP", X, AM, E)
    R("RSETI", ONE, 0, 0, 0, 1); R("RMUL", QI, X, ONE); R("RSTB", QI, 0, 0, 0, desc(TX, SKB + 512, 128))
    wrap_stream(A, desc(TX, 0, 16), 0x45); A.op("SHFIN"); A.op("SHXORKS", 0, 0, 0, 0, desc(TX, SKB, KB))
    wrap_stream(A, desc(TX, 0, 16), 0x4D); A.op("SHABSB", 0, 0, 0, 0, desc(TX, SKB, KB)); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(TX, SKB + KB, 16))
    A.op("FIN", 0, 0, 0, 0, SKB + KB + 16 + 256)
    # ---------------- shared: verify tag, decrypt the key material in place in RX ----------------
    def unwrap():
        wrap_stream(A, desc(RX, 0, 16), 0x4D); A.op("SHABSB", 0, 0, 0, 0, desc(RX, SKB, KB)); A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, SC_TAGC, 16))
        A.op("SETF0"); A.op("BCMP", 0, 0, 0, 0, desc(SC, SC_TAGC, 16), desc(RX, SKB + KB)); A.jump("JF", "auth_fail")
        wrap_stream(A, desc(RX, 0, 16), 0x45); A.op("SHFIN"); A.op("SHXORKS", 0, 0, 0, 0, desc(RX, SKB, KB))
    # ---------------- public modulus ----------------
    A.entries["pub"] = base + len(A.w)
    A.op("CHKLEN", 0, 0, 0, 0, 672); A.jump("JF", "bad_len"); unwrap()
    R("RLDB", 0, 0, 0, 0, desc(RX, SKB, 128)); R("RLDB", 1, 0, 0, 0, desc(RX, SKB + 128, 128)); R("RMULF", 2, 3, 0, 1)
    R("RSTB", 3, 0, 0, 0, desc(TX, 0, 128)); R("RSTB", 2, 0, 0, 0, desc(TX, 128, 128)); A.op("FIN", 0, 0, 0, 0, 256)
    # ---------------- sign ----------------
    A.entries["sign"] = base + len(A.w)
    A.op("CHKLEN", 0, 0, 0, 0, 672 + 32); A.jump("JF", "bad_len"); unwrap()
    A.op("BFILL", 0, 0, 0, 0, desc(SC, 0, 256), 0xFF)
    A.op("WIMM", 0, 0, 0, 0, desc(SC, 0), 0x0001)
    di = bytes.fromhex("003031300d060960864801650304020105000420")
    for k in range(0, len(di), 2): A.op("WIMM", 0, 0, 0, 0, desc(SC, 204 + k), (di[k] << 8) | di[k + 1])
    A.op("BCPY", 0, 0, 0, 0, desc(SC, 224, 32), desc(RX, SKB + KB + 16))
    PR, R2, T, U, MP, X, ONE, E, SQ, SP, DX, D, H = 0, 1, 2, 3, 4, 5, 6, 7, 8, 9, 10, 11, 12
    R("RSETI", E, 0, 0, 0, RSA_E); R("RSETI", ONE, 0, 0, 0, 1)
    def crt_half(prime_off, d_off, out):
        R("RLDB", PR, 0, 0, 0, desc(RX, SKB + prime_off, 128)); R("RMSEL", PR); R("RR2", R2)
        R("RLDB", T, 0, 0, 0, desc(SC, 128, 128)); R("RCSUB", T, T); R("RMUL", T, T, R2)             # EML mod p, then EMH*R
        R("RLDB", U, 0, 0, 0, desc(SC, 0, 128)); R("RCSUB", U, U); R("RMUL", U, U, R2)               # EMH mod p ; EMH*R
        R("RLDB", MP, 0, 0, 0, desc(SC, 128, 128)); R("RCSUB", MP, MP); R("RADDM", MP, MP, U)         # MP = EM mod p
        R("RMUL", X, MP, R2); R("RLDB", DX, 0, 0, 0, desc(RX, SKB + d_off, 128)); R("REXP", X, X, DX); R("RMUL", out, X, ONE)
        R("RMUL", X, out, R2); R("REXP", X, X, E, 2); R("RMUL", X, X, ONE); R("REQ", X, MP); A.jump("JNF", "fault")
    crt_half(128, 384, SQ)
    crt_half(0, 256, SP)
    R("RCSUB", T, SQ); R("RSUBM", D, SP, T); R("RMUL", D, D, R2); R("RLDB", T, 0, 0, 0, desc(RX, SKB + 512, 128)); R("RMUL", H, D, T)
    R("RLDB", T, 0, 0, 0, desc(RX, SKB + 128, 128)); R("RMULF", 2, 3, H, T); R("RADD2", 2, 3, SQ)
    R("RSTB", 3, 0, 0, 0, desc(TX, 0, 128)); R("RSTB", 2, 0, 0, 0, desc(TX, 128, 128)); A.op("FIN", 0, 0, 0, 0, 256)
    A.label("fault"); A.op("FIN", 5, 0, 0, 0, 0)
    A.label("auth_fail"); A.op("FIN", 4, 0, 0, 0, 0)
    A.label("bad_len"); A.op("FIN", 2, 0, 0, 0, 0)
    A.code = A.link(); return A

CAPS_PQ = int(os.environ.get('PQ_CAPS', '0x700'), 16)       # capability bits reported by `ping` (the build script ORs in the other units)
def prog_info(base):
    A = Asm(base); A.entries = {}
    A.entries["ping"] = base
    A.op("CHKLEN", 0, 0, 0, 0, 0); A.jump("JF", "bl")
    for k, v in enumerate((0x5452, 0x4F41, 0x4343, 0x3031, CAPS_PQ >> 16, CAPS_PQ & 0xFFFF)):
        A.op("WIMM", 0, 0, 0, 0, desc(TX, 2 * k), v)
    A.op("FIN", 0, 0, 0, 0, 12)
    A.entries["uid"] = base + len(A.w)
    A.op("CHKLEN", 0, 0, 0, 0, 0); A.jump("JF", "bl"); A.op("WUID", 0, 0, 0, 0, desc(TX, 0)); A.op("FIN", 0, 0, 0, 0, 16)
    A.entries["rand"] = base + len(A.w)
    A.op("CHKLEN", 0, 0, 0, 0, 0); A.jump("JF", "bl"); A.op("RNGB", 0, 0, 0, 0, desc(TX, 0, 32)); A.op("FIN", 0, 0, 0, 0, 32)
    A.label("bl"); A.op("FIN", 2, 0, 0, 0, 0)
    A.code = A.link(); return A


def prog_debug(base):
    """Diagnostic programs: single polynomial operations on fixed inputs, dumped as raw words (1024 B at TX 0)."""
    A = Asm(base); A.entries = {}
    def head(name):
        A.entries[name] = base + len(A.w)
        A.op("PARAM", 0, 0, 0, 0, 39 | (4 << 8) | (80 << 16))
    def samp_u(slot, i, j, key=0):                       # SHAKE128(rx[0:32] | j | i) -> uniform poly
        A.op("SHINIT", 0); A.op("SHABSB", 0, 0, 0, 0, desc(RX, 0, 32)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, i)
        A.op("SHFIN"); A.op("SMPU", slot)
    def dump(slot): A.op("PDUMP", slot, 0, 0, 0, desc(TX, 0)); A.op("FIN", 0, 0, 0, 0, 1024)
    head("dbg_uniform"); samp_u(0, 0, 0); dump(0)
    head("dbg_ntt"); samp_u(0, 0, 0); A.op("PNTT", 0); dump(0)
    head("dbg_pmul"); samp_u(0, 0, 0); samp_u(1, 1, 0); A.op("PMUL", 2, 0, 1); dump(2)
    head("dbg_intt"); samp_u(0, 0, 0); A.op("PINTT", 0); dump(0)
    head("dbg_eta"); A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(RX, 0, 32)); A.op("SHABSB", 0, 0, 0, 0, desc(RX, 0, 32)); A.op("SHABSI", 0, 0, 0, 0, 0)
    A.op("SHABSI", 0, 0, 0, 0, 0); A.op("SHFIN"); A.op("SMPE", 0); dump(0)
    head("dbg_chain"); samp_u(0, 0, 0); A.op("PNTT", 0); samp_u(1, 1, 0); A.op("PMUL", 2, 0, 1); A.op("PRED", 2); A.op("PINTT", 2); A.op("PCADDQ", 2); dump(2)
    # keygen row 0 of ML-DSA-44 with a dump after every stage (7 x 1 KB at TX 0..7167); seed = rx[0:32]
    head("dbg_kg")
    A.op("PARAM", 0, 0, 0, 0, 39 | (4 << 8) | (80 << 16))
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(RX, 0, 32)); A.op("SHABSI", 0, 0, 0, 0, 4); A.op("SHABSI", 0, 0, 0, 0, 4)
    A.op("SHFIN"); A.op("SHSQB", 0, 0, 0, 0, desc(SC, 0, 128))
    for j in range(4):
        A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHOP, 64)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, 0)
        A.op("SHFIN"); A.op("SMPE", 10 + j); A.op("PNTT", 10 + j)
    for j in range(4):
        A.op("SHINIT", 0); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHO, 32)); A.op("SHABSI", 0, 0, 0, 0, j); A.op("SHABSI", 0, 0, 0, 0, 0)
        A.op("SHFIN"); A.op("SMPU", 1); A.op("PMUL" if j == 0 else "PMULA", 0, 1, 10 + j)
    A.op("PDUMP", 0, 0, 0, 0, desc(TX, 0))
    A.op("PRED", 0); A.op("PDUMP", 0, 0, 0, 0, desc(TX, 1024))
    A.op("PINTT", 0); A.op("PDUMP", 0, 0, 0, 0, desc(TX, 2048))
    A.op("SHINIT", 1); A.op("SHABSB", 0, 0, 0, 0, desc(SC, SC_RHOP, 64)); A.op("SHABSI", 0, 0, 0, 0, 4); A.op("SHABSI", 0, 0, 0, 0, 0)
    A.op("SHFIN"); A.op("SMPE", 2); A.op("PDUMP", 2, 0, 0, 0, desc(TX, 3072))
    A.op("PADD", 0, 0, 2); A.op("PDUMP", 0, 0, 0, 0, desc(TX, 4096))
    A.op("PCADDQ", 0); A.op("P2R", 3, 4, 0); A.op("PDUMP", 3, 0, 0, 0, desc(TX, 5120)); A.op("PDUMP", 4, 0, 0, 0, desc(TX, 6144))
    A.op("FIN", 0, 0, 0, 0, 7168)
    A.code = A.link(); return A

DBG = {0x7E: "dbg_kg", 0x78: "dbg_uniform", 0x79: "dbg_ntt", 0x7A: "dbg_pmul", 0x7B: "dbg_intt", 0x7C: "dbg_eta", 0x7D: "dbg_chain"}

PSET = {44: 0, 65: 1, 87: 2}
def build_image():
    """All programs in one ROM image. Returns (words, {cmd: entry address})."""
    words = []; cmds = {}
    A = prog_info(0); words += A.code; cmds[0x01] = A.entries["ping"]; cmds[0x02] = A.entries["uid"]; cmds[0x03] = A.entries["rand"]
    debug = bool(os.environ.get("PQ_DEBUG"))                 # diagnostic image: ML-DSA-44 + single-operation programs only
    for ps, p in (PSET.items() if not debug else [(44, 0)]):
        K = prog_keygen(ps, len(words)); words += K.code; cmds[0x60 + p] = K.entries["trng"]; cmds[0x64 + p] = K.entries["expl"]
        S = prog_sign(ps, len(words)); words += S.code; cmds[0x68 + p] = S.entries["trng"]; cmds[0x6C + p] = S.entries["expl"]
    if not debug:
        R_ = prog_rsa(4096); words += [0] * (4096 - len(words)); words += R_.code; cmds[0x70] = R_.entries["gen"]; cmds[0x71] = R_.entries["pub"]; cmds[0x72] = R_.entries["sign"]
    if debug:
        D = prog_debug(len(words)); words += D.code
        for c, n in DBG.items(): cmds[c] = D.entries[n]
    assert len(words) <= 4096 + 512, len(words)
    return words, cmds

def write_image(outdir):
    words, cmds = build_image()
    with open(os.path.join(outdir, "pq_ucode.vh"), "w") as f:
        f.write("// generated by ref/pq/pq_asm.py: ML-DSA microcode ROM image (%d words)\n" % len(words))
        for i, w in enumerate(words): f.write(f"uc[{i}] = 32'h{w:08x};\n" if i < 4096 else f"uc2[{i - 4096}] = 32'h{w:08x};\n")
    with open(os.path.join(outdir, "pq_cmdtab.vh"), "w") as f:
        f.write("// generated by ref/pq/pq_asm.py: command byte -> microcode entry  ({valid, address[12:0]})\nfunction [13:0] pq_entry(input [7:0] c);\n  case (c)\n")
        for c, e in sorted(cmds.items()): f.write(f"    8'h{c:02x}: pq_entry = {{1'b1, 13'd{e}}};\n")
        f.write("    default: pq_entry = 14'd0;\n  endcase\nendfunction\n")
    return words, cmds

if __name__ == "__main__":
    import subprocess
    master = bytes(range(32)); msg = bytes.fromhex("48656c6c6f")
    words, cmds = write_image(os.environ.get("PQ_OUT") or os.path.join(M.HERE, "..", "..", "rtl_pq"))
    print(len(words), "words in the image; entries", {hex(c): e for c, e in cmds.items()})
    for ps in ((44, 65, 87) if not os.environ.get("PQ_DEBUG") else (44,)):
        p = PSET[ps]
        out = subprocess.run([os.path.join(M.HERE, "golden"), str(ps), "7", msg.hex()], capture_output=True, text=True).stdout
        g = dict(l.split("=") for l in out.split())
        rng = M.CRng(7); seed = rng.read(32); rnd = rng.read(32)
        s = sizes(ps)
        dev = Dev(seed, master, trng=lambda n: bytes(range(100, 100 + n)))
        run(words, cmds[0x64 + p], dev)
        assert dev.fin == (0, 16 + s["sk"] + 16 + s["pk"]), dev.fin
        blob = bytes(dev.tx[:32 + s["sk"]]); pk = bytes(dev.tx[32 + s["sk"]:dev.fin[1]])
        assert pk.hex() == g["pk"], f"pk mismatch {ps}"
        assert blob == wrap_py(master, bytes.fromhex(g["sk"]), bytes(range(100, 116))), f"blob mismatch {ps}"
        dev = Dev(blob + rnd + msg, master); steps = run(words, cmds[0x6C + p], dev)
        assert dev.fin == (0, s["sig"]), dev.fin
        assert bytes(dev.tx[:s["sig"]]).hex() == g["sig"], f"sig mismatch {ps}"
        bad = bytearray(blob); bad[40] ^= 1; dev = Dev(bytes(bad) + rnd + msg, master); run(words, cmds[0x6C + p], dev)
        assert dev.fin[0] == 4
        dev = Dev(b"", master, trng=lambda n: bytes(range(n))); run(words, cmds[0x60 + p], dev); assert dev.fin[0] == 0   # TRNG-seeded keygen
        dev2 = Dev(blob + bytes(32) + msg, master, trng=lambda n: rnd); run(words, cmds[0x68 + p], dev2)
        assert bytes(dev2.tx[:s["sig"]]).hex() == g["sig"]                                                              # TRNG rnd == explicit rnd
        print(f"ML-DSA-{ps}: keygen+sign (explicit and TRNG variants) identical to the C reference; tampered blob rejected")
    dev = Dev(b""); run(words, cmds[0x01], dev); assert dev.fin == (0, 12) and bytes(dev.tx[:8]) == b"TROACC01"
    dev = Dev(b""); run(words, cmds[0x02], dev); assert bytes(dev.tx[:16]) == dev.uid
    dev = Dev(b"", trng=lambda n: bytes(range(n))); run(words, cmds[0x03], dev); assert dev.fin == (0, 32)
    print("info commands OK")
