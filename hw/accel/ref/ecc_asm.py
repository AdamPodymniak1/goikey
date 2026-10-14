#!/usr/bin/env python3
"""Assembler, constant table, microprograms and a reference interpreter for the ECC engine.

ISA (32-bit): [31:24] op  [23:16] d  [15:8] a  [7:0] b   (jump target / SETI imm16 = {a,b})
Registers r0..r127 hold 256-bit values (16 words).  A single flag bit.  HALT leaves the final flag:
by convention flag==1 at HALT means FAILURE.
"""
import sys, os
sys.path.insert(0, os.path.dirname(__file__))
from ecc_model import *

OPS = dict(NOP=0, MUL=1, ADD=2, SUB=3, MOV=4, SEL=5, MSEL=6, LDK=7, BITINIT=8, BITNEXT=9, HALT=10,
           ISZ=11, LT=12, JF=13, JNF=14, JMP=15, SETI=16, NOTF=17, SETF=18,
           XOR=19, AND=20, OR=21, BSWAP=22, RXBE=23, RXLE=24, TXBE=25, TXLE=26, RNG=27, H5BEGIN=28,
           H5FEEDR=29, H5FEEDI=30, H5FILL=31, H5FEEDRX=32, H5END=33, FIN=34, CHKLEN=35, CHKLT=36,
           CALL=37, RET=38, LDUID=39, SHR128=40)
MS_P, MS_N, MS_EP, MS_EL = 0, 1, 2, 3

# ---------------- constant table ----------------
def _mont(x, m): return (x * R) % m
CONSTS = {}
def _c(name, v): CONSTS[name] = v
_c("ZERO", 0); _c("ONE", 1)
_c("P256_P", P256_P); _c("P256_N", P256_N); _c("GXP", P256_GX); _c("GYP", P256_GY)
_c("R2P", (R * R) % P256_P); _c("ONEP", R % P256_P); _c("BP", _mont(P256_B, P256_P)); _c("PM2", P256_P - 2)
_c("R2N", (R * R) % P256_N); _c("ONEN", R % P256_N); _c("NM2", P256_N - 2)
_c("ED_P", ED_P); _c("ED_L", ED_L)
_c("R2E", (R * R) % ED_P); _c("ONEE", R % ED_P); _c("D2E", _mont(2 * ED_D % ED_P, ED_P)); _c("DE", _mont(ED_D, ED_P))
_c("BXE", _mont(ED_BX, ED_P)); _c("BYE", _mont(ED_BY, ED_P)); _c("TBE", _mont(ED_BX * ED_BY % ED_P, ED_P))
_c("PM2E", ED_P - 2); _c("P38E", (ED_P + 3) // 8); _c("SQM1E", _mont(pow(2, (ED_P - 1) // 4, ED_P), ED_P))
_c("R2L", (R * R) % ED_L); _c("ONEL", R % ED_L); _c("LM2", ED_L - 2)
MASTER = bytes(range(32))             # simulation default; the build passes the real one (set_master)
CAPS = 0xF0
def set_master(m):
    global MASTER
    MASTER = m
    _c("IPAD0", int.from_bytes(bytes(b ^ 0x36 for b in m), "big"))
    _c("OPAD0", int.from_bytes(bytes(b ^ 0x5C for b in m), "big"))
_c("IPAD0", 0); _c("OPAD0", 0)
_c("PING", (int.from_bytes(b"TROACC01", "big") << 32) | CAPS)
_c("MASKC", (1 << 254) - 8); _c("BIT254", 1 << 254); _c("HIGHBIT", 1 << 255)
set_master(MASTER)
CNAMES = list(CONSTS)
def cidx(n): return CNAMES.index(n)

# ---------------- assembler ----------------
class Asm:
    def __init__(self):
        self.code = []; self.labels = {}; self.fix = []; self.regs = {}; self.entries = {}
    def reg(self, n):
        if n not in self.regs:
            assert len(self.regs) < 128, "out of registers: " + n
            self.regs[n] = len(self.regs)
        return self.regs[n]
    def regmap(self, names):
        for n in names: self.reg(n)
    def emit(self, op, d=0, a=0, b=0): self.code.append((OPS[op] << 24) | (d << 16) | (a << 8) | b)
    def label(self, n): self.labels[n] = len(self.code)
    def entry(self, n): self.entries[n] = len(self.code); self.label("entry_" + n)
    # ops
    def mul(self, d, a, b): self.emit("MUL", self.reg(d), self.reg(a), self.reg(b))
    def add(self, d, a, b): self.emit("ADD", self.reg(d), self.reg(a), self.reg(b))
    def sub(self, d, a, b): self.emit("SUB", self.reg(d), self.reg(a), self.reg(b))
    def mov(self, d, a): self.emit("MOV", self.reg(d), self.reg(a))
    def sel(self, d, a, b): self.emit("SEL", self.reg(d), self.reg(a), self.reg(b))
    def msel(self, m): self.emit("MSEL", 0, 0, m)
    def ldk(self, d, name): self.emit("LDK", self.reg(d), 0, cidx(name))
    def bitinit(self, a, n): self.emit("BITINIT", 0, self.reg(a), n & 255)
    def bitnext(self): self.emit("BITNEXT")
    def halt(self): self.emit("HALT")
    def isz(self, a): self.emit("ISZ", 0, self.reg(a))
    def lt(self, a, b): self.emit("LT", 0, self.reg(a), self.reg(b))
    def seti(self, d, v): self.emit("SETI", self.reg(d), (v >> 8) & 255, v & 255)
    def notf(self): self.emit("NOTF")
    def xor(self, d, a, b): self.emit("XOR", self.reg(d), self.reg(a), self.reg(b))
    def and_(self, d, a, b): self.emit("AND", self.reg(d), self.reg(a), self.reg(b))
    def or_(self, d, a, b): self.emit("OR", self.reg(d), self.reg(a), self.reg(b))
    def bswap(self, d, a): self.emit("BSWAP", self.reg(d), self.reg(a), 0)
    def shr128(self, d, a): self.emit("SHR128", self.reg(d), self.reg(a))
    def rxbe(self, d, off, n): self.emit("RXBE", self.reg(d), off, n)
    def rxle(self, d, off, n): self.emit("RXLE", self.reg(d), off, n)
    def txbe(self, s_, off, n): self._tx("TXBE", s_, off, n)
    def txle(self, s_, off, n): self._tx("TXLE", s_, off, n)
    def _tx(self, op, s_, off, n):
        assert off < 256 and 1 <= n <= 32          # fields: d = source reg, a = response offset, b = byte count
        self.emit(op, self.reg(s_), off, n)
    def rng(self, d, nw): self.emit("RNG", self.reg(d), 0, nw)
    def lduid(self, d): self.emit("LDUID", self.reg(d))
    def h5begin(self): self.emit("H5BEGIN")
    def h5feedr(self, a, n): self.emit("H5FEEDR", 0, self.reg(a), n)
    def h5feedi(self, v): self.emit("H5FEEDI", 0, 0, v)
    def h5fill(self, v, n): self.emit("H5FILL", 0, v, n)
    def h5feedrx(self, off): self.emit("H5FEEDRX", 0, off, 0)
    def h5end(self, d1, d2): self.emit("H5END", self.reg(d1), self.reg(d2), 0)
    def fin(self, status, ln): self.emit("FIN", status, (ln >> 8) & 255, ln & 255)
    def chklen(self, n): self.emit("CHKLEN", 0, (n >> 8) & 255, n & 255)
    def chklt(self, n): self.emit("CHKLT", 0, (n >> 8) & 255, n & 255)
    def call(self, lab): self._j("CALL", lab)
    def ret(self): self.emit("RET")
    def setf(self, v): self.emit("SETF", 0, 0, v)
    def _j(self, op, lab): self.fix.append((len(self.code), lab)); self.emit(op)
    def jf(self, l): self._j("JF", l)
    def jnf(self, l): self._j("JNF", l)
    def jmp(self, l): self._j("JMP", l)
    def link(self):
        for pc, lab in self.fix:
            t = self.labels[lab]; self.code[pc] |= ((t >> 8) << 8) | (t & 255)
        return self.code

# ---------------- reference interpreter (same semantics as the RTL) ----------------
class Dev:
    """Device model: request payload, response buffer, TRNG, UID and the SHA-512 unit."""
    def __init__(self, payload=b"", uid=bytes(16), rng=None):
        import random as _r
        self.payload = payload; self.tx = bytearray(8192); self.uid = uid
        self.rng = rng or _r.Random(1); self.h5 = bytearray(); self.fin = None
        self.txlen = 0

def run(code, pc, regs, consts=CONSTS, dev=None, maxsteps=10**9):
    """regs: dict index->int. Returns (regs, flag, steps). With `dev`, FIN records (status,len) in dev.fin."""
    import hashlib as _h
    ms = 0; flag = 0; bitctr = 0; bsrc = 0; loop_pc = 0; steps = 0; stack = []
    mods = [P256_P, P256_N, ED_P, ED_L]
    rg = lambda i: regs.get(i, 0)
    M256 = (1 << 256) - 1
    while steps < maxsteps:
        ins = code[pc]; op = ins >> 24; d = (ins >> 16) & 255; a = (ins >> 8) & 255; b = ins & 255
        steps += 1; cur = pc; pc += 1; m = mods[ms]
        if op == OPS["MUL"]: regs[d] = mont_mul(rg(a), rg(b), m)
        elif op == OPS["ADD"]:
            t = rg(a) + rg(b); regs[d] = (t - m) if t >= m else t
        elif op == OPS["SUB"]:
            x = rg(a) - rg(b); regs[d] = (x + m) if x < 0 else x
        elif op == OPS["MOV"]: regs[d] = rg(a)
        elif op == OPS["SEL"]: regs[d] = rg(a) if (rg(bsrc) >> bitctr) & 1 else rg(b)
        elif op == OPS["MSEL"]: ms = b
        elif op == OPS["LDK"]: regs[d] = consts[CNAMES[b]]
        elif op == OPS["BITINIT"]: bsrc = a; bitctr = (b - 1) if b else 255; loop_pc = pc
        elif op == OPS["BITNEXT"]:
            if bitctr: bitctr -= 1; pc = loop_pc
        elif op == OPS["HALT"]: return regs, flag, steps
        elif op == OPS["RET"]:
            if not stack: return regs, flag, steps
            pc = stack.pop()
        elif op == OPS["CALL"]: stack.append(pc); pc = (a << 8) | b
        elif op == OPS["ISZ"]: flag = int(rg(a) == 0)
        elif op == OPS["LT"]: flag = int(rg(a) < rg(b))
        elif op == OPS["JF"]:
            if flag: pc = (a << 8) | b
        elif op == OPS["JNF"]:
            if not flag: pc = (a << 8) | b
        elif op == OPS["JMP"]: pc = (a << 8) | b
        elif op == OPS["SETI"]: regs[d] = (a << 8) | b
        elif op == OPS["NOTF"]: flag ^= 1
        elif op == OPS["SETF"]: flag = b & 1
        elif op == OPS["NOP"]: pass
        elif op == OPS["XOR"]: regs[d] = rg(a) ^ rg(b)
        elif op == OPS["AND"]: regs[d] = rg(a) & rg(b)
        elif op == OPS["OR"]:  regs[d] = rg(a) | rg(b)
        elif op == OPS["BSWAP"]: regs[d] = int.from_bytes(rg(a).to_bytes(32, "big"), "little")
        elif op == OPS["SHR128"]: regs[d] = rg(a) >> 128
        elif op == OPS["LDUID"]: regs[d] = int.from_bytes(dev.uid, "big")
        elif op == OPS["RXBE"]: regs[d] = int.from_bytes(dev.payload[a:a + b], "big")
        elif op == OPS["RXLE"]: regs[d] = int.from_bytes(dev.payload[a:a + b], "little")
        elif op == OPS["TXBE"]:
            dev.tx[a:a + b] = (rg(d) & ((1 << (8 * b)) - 1)).to_bytes(b, "big")
        elif op == OPS["TXLE"]:
            dev.tx[a:a + b] = (rg(d) & ((1 << (8 * b)) - 1)).to_bytes(b, "little")
        elif op == OPS["RNG"]: regs[d] = dev.rng.getrandbits(32 * b)
        elif op == OPS["H5BEGIN"]: dev.h5 = bytearray()
        elif op == OPS["H5FEEDR"]: dev.h5 += (rg(a) & ((1 << (8 * b)) - 1)).to_bytes(b, "big")
        elif op == OPS["H5FEEDI"]: dev.h5.append(b)
        elif op == OPS["H5FILL"]: dev.h5 += bytes([a]) * b
        elif op == OPS["H5FEEDRX"]: dev.h5 += dev.payload[a:]
        elif op == OPS["H5END"]:
            dg = _h.sha512(bytes(dev.h5)).digest()
            regs[d] = int.from_bytes(dg[:32], "big"); regs[a] = int.from_bytes(dg[32:], "big")
        elif op == OPS["CHKLEN"]: flag = int(len(dev.payload) != ((a << 8) | b))
        elif op == OPS["CHKLT"]: flag = int(len(dev.payload) < ((a << 8) | b))
        elif op == OPS["FIN"]:
            dev.fin = (d, (a << 8) | b); return regs, flag, steps
        else: raise ValueError(f"bad opcode {op} at {cur}")
    raise RuntimeError("step limit")

# ---------------- P-256 building blocks (formulas transcribed from the verified model) ----------------
def p256_dbl_prog(A, X, Y, Z, X3, Y3, Z3, b):
    m, a, s = A.mul, A.add, A.sub
    t0, t1, t2, t3 = "t0", "t1", "t2", "t3"
    m(t0, X, X); m(t1, Y, Y); m(t2, Z, Z); m(t3, X, Y); a(t3, t3, t3)
    m(Z3, X, Z); a(Z3, Z3, Z3); m(Y3, b, t2); s(Y3, Y3, Z3); a(X3, Y3, Y3)
    a(Y3, X3, Y3); s(X3, t1, Y3); a(Y3, t1, Y3); m(Y3, X3, Y3); m(X3, X3, t3)
    a(t3, t2, t2); a(t2, t2, t3); m(Z3, b, Z3); s(Z3, Z3, t2); s(Z3, Z3, t0)
    a(t3, Z3, Z3); a(Z3, Z3, t3); a(t3, t0, t0); a(t0, t3, t0); s(t0, t0, t2)
    m(t0, t0, Z3); a(Y3, Y3, t0); m(t0, Y, Z); a(t0, t0, t0); m(Z3, t0, Z3)
    s(X3, X3, Z3); m(Z3, t0, t1); a(Z3, Z3, Z3); a(Z3, Z3, Z3)

def p256_add_prog(A, X1, Y1, Z1, X2, Y2, Z2, X3, Y3, Z3, b):
    m, a, s = A.mul, A.add, A.sub
    t0, t1, t2, t3, t4 = "t0", "t1", "t2", "t3", "t4"
    m(t0, X1, X2); m(t1, Y1, Y2); m(t2, Z1, Z2)
    a(t3, X1, Y1); a(t4, X2, Y2); m(t3, t3, t4); a(t4, t0, t1); s(t3, t3, t4)
    a(t4, Y1, Z1); a(X3, Y2, Z2); m(t4, t4, X3); a(X3, t1, t2); s(t4, t4, X3)
    a(X3, X1, Z1); a(Y3, X2, Z2); m(X3, X3, Y3); a(Y3, t0, t2); s(Y3, X3, Y3)
    m(Z3, b, t2); s(X3, Y3, Z3); a(Z3, X3, X3); a(X3, X3, Z3); s(Z3, t1, X3)
    a(X3, t1, X3); m(Y3, b, Y3); a(t1, t2, t2); a(t2, t1, t2); s(Y3, Y3, t2)
    s(Y3, Y3, t0); a(t1, Y3, Y3); a(Y3, t1, Y3); a(t1, t0, t0); a(t0, t1, t0)
    s(t0, t0, t2); m(t1, t4, Y3); m(t2, t0, Y3); m(Y3, X3, Z3); a(Y3, Y3, t2)
    m(X3, t3, X3); s(X3, X3, t1); m(Z3, t4, Z3); m(t1, t3, t0); a(Z3, Z3, t1)

def fermat_inv(A, dst, src, one, expreg, scr):
    """dst = src^(m-2) in the Montgomery domain, bits taken from `expreg`; clobbers `scr`."""
    A.mov(dst, one)
    A.bitinit(expreg, 256)
    A.mul(dst, dst, dst); A.mul(scr, dst, src); A.sel(dst, scr, dst)
    A.bitnext()

def check_range(A, reg, nreg, fail):
    """fail unless 0 < reg < N (plain compare against constant register nreg)."""
    A.isz(reg); A.jf(fail); A.lt(reg, nreg); A.jnf(fail)

def p256_scalarmul(A, K, PXm, PYm, ONE_M, bcoef, RX, RY, RZ):
    """R = K * (PXm, PYm) in projective Montgomery coords. Modulus must be p."""
    A.seti(RX, 0); A.mov(RY, ONE_M); A.seti(RZ, 0)
    A.bitinit(K, 256)
    p256_dbl_prog(A, RX, RY, RZ, "TX", "TY", "TZ", bcoef)
    A.mov(RX, "TX"); A.mov(RY, "TY"); A.mov(RZ, "TZ")
    p256_add_prog(A, RX, RY, RZ, PXm, PYm, ONE_M, "TX", "TY", "TZ", bcoef)
    A.sel(RX, "TX", RX); A.sel(RY, "TY", RY); A.sel(RZ, "TZ", RZ)
    A.bitnext()

def p256_load_consts(A):
    A.msel(MS_P); A.ldk("BC", "BP"); A.ldk("ONE_M", "ONEP")

def p256_core(A):
    """Inputs K, PX, PY (plain). Outputs OX, OY (plain affine); RZ left for the infinity test."""
    p256_load_consts(A)
    A.ldk("c1", "R2P"); A.mul("PXm", "PX", "c1"); A.mul("PYm", "PY", "c1")
    p256_scalarmul(A, "K", "PXm", "PYm", "ONE_M", "BC", "RX", "RY", "RZ")
    A.ldk("e", "PM2"); fermat_inv(A, "w", "RZ", "ONE_M", "e", "t0")
    A.ldk("c2", "ONE")
    A.mul("OX", "RX", "w"); A.mul("OX", "OX", "c2")
    A.mul("OY", "RY", "w"); A.mul("OY", "OY", "c2")

def p256_oncurve(A, x, y, fail):
    """Jump to `fail` unless (x,y) (plain) satisfies y^2 = x^3 - 3x + b with x,y < p. Leaves modulus p."""
    A.msel(MS_P); A.ldk("c3", "P256_P")
    A.lt(x, "c3"); A.jnf(fail); A.lt(y, "c3"); A.jnf(fail)
    A.ldk("c1", "R2P"); A.ldk("BC", "BP")
    A.mul("t0", x, "c1"); A.mul("t1", y, "c1")
    A.mul("t2", "t0", "t0"); A.mul("t2", "t2", "t0")         # x^3
    A.add("t3", "t0", "t0"); A.add("t3", "t3", "t0")         # 3x
    A.sub("t2", "t2", "t3"); A.add("t2", "t2", "BC")         # x^3 - 3x + b
    A.mul("t1", "t1", "t1")                                  # y^2
    A.sub("t1", "t1", "t2"); A.isz("t1"); A.notf(); A.jf(fail)

def ed_add_prog(A, P, Q, O):
    X1, Y1, Z1, T1 = P; X2, Y2, Z2, T2 = Q; X3, Y3, Z3, T3 = O
    A.sub("Ea", Y1, X1); A.sub("t0", Y2, X2); A.mul("Ea", "Ea", "t0")
    A.add("Eb", Y1, X1); A.add("t0", Y2, X2); A.mul("Eb", "Eb", "t0")
    A.mul("Ec", T1, "D2"); A.mul("Ec", "Ec", T2)
    A.mul("Ed", Z1, Z2); A.add("Ed", "Ed", "Ed")
    A.sub("Ee", "Eb", "Ea"); A.sub("Ef", "Ed", "Ec"); A.add("Eg", "Ed", "Ec"); A.add("Eh", "Eb", "Ea")
    A.mul(X3, "Ee", "Ef"); A.mul(Y3, "Eg", "Eh"); A.mul(Z3, "Ef", "Eg"); A.mul(T3, "Ee", "Eh")

def ed_scalarmul(A, K, nbits=256):
    """R = K*(PXm,PYm,ONE_M,PTm) extended Montgomery coords in EX,EY,EZ,ET. Modulus must be Ed25519 p."""
    A.seti("EX", 0); A.mov("EY", "ONE_M"); A.mov("EZ", "ONE_M"); A.seti("ET", 0)
    A.bitinit(K, nbits)
    ed_add_prog(A, ("EX", "EY", "EZ", "ET"), ("EX", "EY", "EZ", "ET"), ("FX", "FY", "FZ", "FT"))
    ed_add_prog(A, ("FX", "FY", "FZ", "FT"), ("PXm", "PYm", "ONE_M", "PTm"), ("GX", "GY", "GZ", "GT"))
    A.sel("EX", "GX", "FX"); A.sel("EY", "GY", "FY"); A.sel("EZ", "GZ", "FZ"); A.sel("ET", "GT", "FT")
    A.bitnext()

def ed_affine_out(A):
    A.ldk("e", "PM2E"); fermat_inv(A, "w", "EZ", "ONE_M", "e", "t0")
    A.ldk("c2", "ONE")
    A.mul("OX", "EX", "w"); A.mul("OX", "OX", "c2")
    A.mul("OY", "EY", "w"); A.mul("OY", "OY", "c2")
    A.isz("EZ")

NAMES = ["K", "PX", "PY", "OX", "OY", "D", "Z", "RR", "S", "QX", "QY",          # host I/O (fixed indices 0..10)
         "KK", "AA", "H0", "H1",                                                  # 11..14 (Ed25519 I/O)
         "PXm", "PYm", "PTm", "RX", "RY", "RZ", "TX", "TY", "TZ", "BC", "ONE_M", "AX", "AY", "AZ", "D2",
         "t0", "t1", "t2", "t3", "t4", "u", "w", "e", "c1", "c2", "c3",
         "EX", "EY", "EZ", "ET", "FX", "FY", "FZ", "FT", "GX", "GY", "GZ", "GT",
         "Ea", "Eb", "Ec", "Ed", "Ee", "Ef", "Eg", "Eh",
         # command-level temporaries
         "NONCE", "CT", "TAGRX", "TAGC", "SEC", "KS", "T1", "T2", "KI", "KO", "TRY", "CC", "HA", "HB",
         "PUBR", "PFX", "RENC", "RL", "SGS", "ENCI", "OYH", "VX"]

def build():
    A = Asm(); A.regmap(NAMES)
    # ---------------- P-256 ----------------
    A.entry("P256_BASEMUL")                                  # OX,OY = K*G
    A.ldk("PX", "GXP"); A.ldk("PY", "GYP"); A.jmp("p256_mul_body")
    A.entry("P256_MUL")                                      # OX,OY = K*(PX,PY)
    A.label("p256_mul_body")
    p256_core(A); A.isz("RZ"); A.ret()

    A.entry("P256_ONCURVE")                                  # fail unless (PX,PY) is on the curve
    p256_oncurve(A, "PX", "PY", "f_oc"); A.setf(0); A.ret()
    A.label("f_oc"); A.setf(1); A.ret()

    A.entry("P256_ECDH")                                     # OX = x(D*Q); in: D, QX, QY
    A.msel(MS_N); A.ldk("c3", "P256_N"); check_range(A, "D", "c3", "f_dh")
    p256_oncurve(A, "QX", "QY", "f_dh")
    A.mov("K", "D"); A.mov("PX", "QX"); A.mov("PY", "QY")
    p256_core(A); A.isz("RZ"); A.ret()
    A.label("f_dh"); A.setf(1); A.ret()

    A.entry("P256_KEYGEN")                                   # OX,OY = D*G, fail if D not in [1,n-1]
    A.msel(MS_N); A.ldk("c3", "P256_N"); check_range(A, "D", "c3", "f_kg")
    A.mov("K", "D"); A.ldk("PX", "GXP"); A.ldk("PY", "GYP")
    p256_core(A); A.isz("RZ"); A.ret()
    A.label("f_kg"); A.setf(1); A.ret()

    A.entry("P256_SIGN")                                     # in D, Z, K(nonce); out RR=r, S=s
    A.msel(MS_N); A.ldk("c3", "P256_N")
    check_range(A, "K", "c3", "f_sg"); check_range(A, "D", "c3", "f_sg")
    A.ldk("PX", "GXP"); A.ldk("PY", "GYP")
    p256_core(A); A.isz("RZ"); A.jf("f_sg")
    A.msel(MS_N); A.ldk("c2", "ZERO"); A.add("RR", "OX", "c2")        # r = x mod n
    A.isz("RR"); A.jf("f_sg")
    A.ldk("c1", "R2N"); A.ldk("ONE_M", "ONEN")
    A.mul("t0", "RR", "c1"); A.mul("t1", "D", "c1"); A.mul("t2", "Z", "c1"); A.mul("t3", "K", "c1")
    A.mul("t4", "t0", "t1"); A.add("u", "t2", "t4")                     # z + r*d
    A.ldk("e", "NM2"); fermat_inv(A, "w", "t3", "ONE_M", "e", "t0")     # k^-1
    A.mul("S", "w", "u"); A.ldk("c2", "ONE"); A.mul("S", "S", "c2")
    A.isz("S"); A.jf("f_sg"); A.setf(0); A.ret()
    A.label("f_sg"); A.setf(1); A.ret()

    A.entry("P256_VERIFY")                                   # in Z, RR=r, S=s, QX, QY; fail flag
    A.msel(MS_N); A.ldk("c3", "P256_N")
    check_range(A, "RR", "c3", "f_vf"); check_range(A, "S", "c3", "f_vf")
    p256_oncurve(A, "QX", "QY", "f_vf")
    A.msel(MS_N); A.ldk("c1", "R2N"); A.ldk("ONE_M", "ONEN"); A.ldk("c2", "ONE")
    A.mul("t3", "S", "c1")
    A.ldk("e", "NM2"); fermat_inv(A, "w", "t3", "ONE_M", "e", "t0")     # s^-1 (Mont)
    A.mul("t1", "Z", "c1"); A.mul("t2", "RR", "c1")
    A.mul("t1", "t1", "w"); A.mul("t2", "t2", "w")
    A.mul("K", "t1", "c2")                                              # u1 (plain)
    A.mul("u", "t2", "c2")                                              # u2 (plain)
    A.msel(MS_P); A.ldk("c1", "R2P"); p256_load_consts(A)
    A.ldk("PX", "GXP"); A.ldk("PY", "GYP")
    A.mul("PXm", "PX", "c1"); A.mul("PYm", "PY", "c1")
    p256_scalarmul(A, "K", "PXm", "PYm", "ONE_M", "BC", "RX", "RY", "RZ")   # u1*G
    A.mov("AX", "RX"); A.mov("AY", "RY"); A.mov("AZ", "RZ")
    A.mul("PXm", "QX", "c1"); A.mul("PYm", "QY", "c1")
    A.mov("K", "u")
    p256_scalarmul(A, "K", "PXm", "PYm", "ONE_M", "BC", "RX", "RY", "RZ")   # u2*Q
    p256_add_prog(A, "AX", "AY", "AZ", "RX", "RY", "RZ", "TX", "TY", "TZ", "BC")
    A.isz("TZ"); A.jf("f_vf")
    A.ldk("e", "PM2"); fermat_inv(A, "w", "TZ", "ONE_M", "e", "t0")
    A.ldk("c2", "ONE"); A.mul("OX", "TX", "w"); A.mul("OX", "OX", "c2")
    A.msel(MS_N); A.ldk("c2", "ZERO"); A.add("OX", "OX", "c2")          # x mod n
    A.sub("t0", "OX", "RR"); A.isz("t0"); A.notf(); A.ret()
    A.label("f_vf"); A.setf(1); A.ret()

    # ---------------- Ed25519 ----------------
    A.entry("ED_BASEMUL")                                    # OX,OY = K*B
    A.msel(MS_EP); A.ldk("ONE_M", "ONEE"); A.ldk("D2", "D2E")
    A.ldk("PXm", "BXE"); A.ldk("PYm", "BYE"); A.ldk("PTm", "TBE")
    ed_scalarmul(A, "K"); ed_affine_out(A); A.ret()

    A.entry("ED_MUL")                                        # OX,OY = K*(PX,PY)
    A.msel(MS_EP); A.ldk("ONE_M", "ONEE"); A.ldk("D2", "D2E"); A.ldk("c1", "R2E")
    A.mul("PXm", "PX", "c1"); A.mul("PYm", "PY", "c1"); A.mul("PTm", "PXm", "PYm")
    ed_scalarmul(A, "K"); ed_affine_out(A); A.ret()

    A.entry("ED_REDUCE512")                                  # RR = (H1*2^256 + H0) mod l
    A.msel(MS_EL); A.ldk("c1", "R2L"); A.ldk("c2", "ONE")
    A.mul("t0", "H0", "c1"); A.mul("t0", "t0", "c2")         # H0 mod l
    A.mul("t1", "H1", "c1")                                  # H1 * 2^256 mod l
    A.add("RR", "t0", "t1"); A.setf(0); A.ret()

    A.entry("ED_SIGN_S")                                     # S = (RR + KK*AA) mod l ; RR<l
    A.msel(MS_EL); A.ldk("c1", "R2L"); A.ldk("c2", "ONE")
    A.mul("t0", "KK", "c1"); A.mul("t1", "AA", "c1"); A.mul("t0", "t0", "t1"); A.mul("t0", "t0", "c2")
    A.add("S", "RR", "t0"); A.setf(0); A.ret()
    A.label("zeroize")                                       # wipe every register (secrets!)
    for n in NAMES: A.seti(n, 0)
    A.setf(0); A.ret()
    A.entry("ZEROIZE"); A.jmp("zeroize")

    # ---------------- key wrapping (HMAC-SHA512 keyed with the device MASTER) ----------------
    A.label("hmac_E")                                        # KS = HMAC(MASTER, 'E' | NONCE)[0:32]
    A.ldk("KI", "IPAD0"); A.ldk("KO", "OPAD0")
    A.h5begin(); A.h5feedr("KI", 32); A.h5fill(0x36, 96); A.h5feedi(0x45); A.h5feedr("NONCE", 16); A.h5end("T1", "T2")
    A.h5begin(); A.h5feedr("KO", 32); A.h5fill(0x5C, 96); A.h5feedr("T1", 32); A.h5feedr("T2", 32); A.h5end("KS", "T2")
    A.ret()
    A.label("hmac_M")                                        # TAGC = HMAC(MASTER, 'M' | NONCE | CT)[0:16]
    A.ldk("KI", "IPAD0"); A.ldk("KO", "OPAD0")
    A.h5begin(); A.h5feedr("KI", 32); A.h5fill(0x36, 96); A.h5feedi(0x4D); A.h5feedr("NONCE", 16); A.h5feedr("CT", 32); A.h5end("T1", "T2")
    A.h5begin(); A.h5feedr("KO", 32); A.h5fill(0x5C, 96); A.h5feedr("T1", 32); A.h5feedr("T2", 32); A.h5end("T1", "T2")
    A.shr128("TAGC", "T1"); A.ret()
    A.label("unwrap")                                        # blob at payload[0:64] -> SEC; flag=1 on auth failure
    A.rxbe("NONCE", 0, 16); A.rxbe("CT", 16, 32); A.rxbe("TAGRX", 48, 16)
    A.call("hmac_M"); A.xor("T1", "TAGC", "TAGRX"); A.isz("T1"); A.notf(); A.jf("unwrap_fail")
    A.call("hmac_E"); A.xor("SEC", "CT", "KS"); A.setf(0); A.ret()
    A.label("unwrap_fail"); A.setf(1); A.ret()
    A.label("wrap_new")                                      # SEC -> NONCE, CT, TAG
    A.rng("NONCE", 4); A.call("hmac_E"); A.xor("CT", "SEC", "KS"); A.call("hmac_M"); A.mov("TAG", "TAGC"); A.ret()
    def emit_blob(off):
        A.txbe("NONCE", off, 16); A.txbe("CT", off + 16, 32); A.txbe("TAG", off + 48, 16)
    A.label("ed_expand_pub")                                 # SEC=seed -> AA (clamped scalar), PFX, PUBR (32-byte encoding)
    A.h5begin(); A.h5feedr("SEC", 32); A.h5end("HA", "HB")
    A.bswap("T1", "HA"); A.ldk("c1", "MASKC"); A.and_("T1", "T1", "c1"); A.ldk("c1", "BIT254"); A.or_("AA", "T1", "c1")
    A.mov("PFX", "HB"); A.mov("K", "AA")
    A.call("entry_ED_BASEMUL")
    A.ldk("c1", "HIGHBIT"); A.or_("OYH", "OY", "c1"); A.bitinit("OX", 1); A.sel("ENCI", "OYH", "OY")
    A.bswap("PUBR", "ENCI"); A.ret()

    def retry_or_fail(label_retry, fail_label):
        A.label(label_retry)
        A.msel(MS_P); A.seti("CC", 1); A.add("TRY", "TRY", "CC"); A.seti("CC", 8); A.sub("T1", "TRY", "CC")
        A.isz("T1"); A.jf(fail_label)

    # ---------------- commands (entry order = dispatch table) ----------------
    A.entry("CMD_PING")
    A.chklen(0); A.jf("F_LEN"); A.ldk("T1", "PING"); A.txbe("T1", 0, 12); A.fin(0, 12)
    A.entry("CMD_UID")
    A.chklen(0); A.jf("F_LEN"); A.lduid("T1"); A.txbe("T1", 0, 16); A.fin(0, 16)
    A.entry("CMD_RAND")                                      # 32 random bytes
    A.chklen(0); A.jf("F_LEN"); A.rng("T1", 8); A.txbe("T1", 0, 32); A.seti("T1", 0); A.fin(0, 32)

    A.entry("CMD_P256_GEN")
    A.chklen(0); A.jf("F_LEN"); A.seti("TRY", 0)
    A.label("gen_try")
    A.rng("SEC", 8); A.mov("D", "SEC"); A.call("entry_P256_KEYGEN"); A.jf("gen_retry")
    A.call("wrap_new"); emit_blob(0); A.txbe("OX", 64, 32); A.txbe("OY", 96, 32)
    A.call("zeroize"); A.fin(0, 128)
    retry_or_fail("gen_retry", "F_ERR"); A.jmp("gen_try")

    A.entry("CMD_P256_PUB")
    A.chklen(64); A.jf("F_LEN"); A.call("unwrap"); A.jf("F_AUTH")
    A.mov("D", "SEC"); A.call("entry_P256_KEYGEN"); A.jf("F_PARAM")
    A.txbe("OX", 0, 32); A.txbe("OY", 32, 32); A.call("zeroize"); A.fin(0, 64)

    A.entry("CMD_P256_SIGN")
    A.chklen(96); A.jf("F_LEN"); A.call("unwrap"); A.jf("F_AUTH")
    A.rxbe("Z", 64, 32); A.seti("TRY", 0)
    A.label("sign_try")
    A.rng("K", 8); A.mov("D", "SEC"); A.call("entry_P256_SIGN"); A.jf("sign_retry")
    A.txbe("RR", 0, 32); A.txbe("S", 32, 32); A.call("zeroize"); A.fin(0, 64)
    retry_or_fail("sign_retry", "F_ERR"); A.jmp("sign_try")

    A.entry("CMD_P256_ECDH")
    A.chklen(128); A.jf("F_LEN"); A.call("unwrap"); A.jf("F_AUTH")
    A.rxbe("QX", 64, 32); A.rxbe("QY", 96, 32); A.mov("D", "SEC")
    A.call("entry_P256_ECDH"); A.jf("F_PARAM")
    A.txbe("OX", 0, 32); A.call("zeroize"); A.fin(0, 32)

    A.entry("CMD_P256_VERIFY")
    A.chklen(160); A.jf("F_LEN")
    A.rxbe("Z", 0, 32); A.rxbe("RR", 32, 32); A.rxbe("S", 64, 32); A.rxbe("QX", 96, 32); A.rxbe("QY", 128, 32)
    A.call("entry_P256_VERIFY"); A.jf("v_bad")
    A.call("zeroize"); A.fin(0, 0)
    A.label("v_bad"); A.call("zeroize"); A.fin(4, 0)

    A.entry("CMD_P256_WRAP")
    A.chklen(32); A.jf("F_LEN"); A.rxbe("SEC", 0, 32); A.mov("D", "SEC"); A.call("entry_P256_KEYGEN"); A.jf("F_PARAM")
    A.call("wrap_new"); emit_blob(0); A.call("zeroize"); A.fin(0, 64)

    A.entry("CMD_ED_GEN")
    A.chklen(0); A.jf("F_LEN"); A.rng("SEC", 8); A.call("ed_expand_pub")
    A.call("wrap_new"); emit_blob(0); A.txbe("PUBR", 64, 32); A.call("zeroize"); A.fin(0, 96)

    A.entry("CMD_ED_PUB")
    A.chklen(64); A.jf("F_LEN"); A.call("unwrap"); A.jf("F_AUTH"); A.call("ed_expand_pub")
    A.txbe("PUBR", 0, 32); A.call("zeroize"); A.fin(0, 32)

    A.entry("CMD_ED_SIGN")
    A.chklt(64); A.jf("F_LEN"); A.call("unwrap"); A.jf("F_AUTH"); A.call("ed_expand_pub")
    A.h5begin(); A.h5feedr("PFX", 32); A.h5feedrx(64); A.h5end("HA", "HB")                 # r = SHA512(prefix|M) mod l
    A.bswap("H0", "HA"); A.bswap("H1", "HB"); A.call("entry_ED_REDUCE512"); A.mov("RL", "RR")
    A.mov("K", "RL"); A.call("entry_ED_BASEMUL")                                           # R = r*B
    A.ldk("c1", "HIGHBIT"); A.or_("OYH", "OY", "c1"); A.bitinit("OX", 1); A.sel("ENCI", "OYH", "OY"); A.bswap("RENC", "ENCI")
    A.h5begin(); A.h5feedr("RENC", 32); A.h5feedr("PUBR", 32); A.h5feedrx(64); A.h5end("HA", "HB")   # k = SHA512(R|A|M) mod l
    A.bswap("H0", "HA"); A.bswap("H1", "HB"); A.call("entry_ED_REDUCE512"); A.mov("KK", "RR"); A.mov("RR", "RL")
    A.call("entry_ED_SIGN_S"); A.bswap("SGS", "S")
    A.txbe("RENC", 0, 32); A.txbe("SGS", 32, 32); A.call("zeroize"); A.fin(0, 64)

    A.entry("CMD_ED_WRAP")
    A.chklen(32); A.jf("F_LEN"); A.rxbe("SEC", 0, 32); A.call("wrap_new"); emit_blob(0); A.call("zeroize"); A.fin(0, 64)

    A.entry("CMD_SHA512")
    A.h5begin(); A.h5feedrx(0); A.h5end("HA", "HB"); A.txbe("HA", 0, 32); A.txbe("HB", 32, 32); A.fin(0, 64)

    A.label("F_LEN");   A.fin(2, 0)
    A.label("F_AUTH");  A.call("zeroize"); A.fin(4, 0)
    A.label("F_PARAM"); A.call("zeroize"); A.fin(6, 0)
    A.label("F_ERR");   A.call("zeroize"); A.fin(5, 0)
    return A

CMD_TABLE = {0x01: "CMD_PING", 0x02: "CMD_UID", 0x03: "CMD_RAND", 0x30: "CMD_P256_GEN", 0x31: "CMD_P256_PUB",
             0x32: "CMD_P256_SIGN", 0x33: "CMD_P256_ECDH", 0x34: "CMD_P256_VERIFY", 0x35: "CMD_P256_WRAP",
             0x40: "CMD_ED_GEN", 0x41: "CMD_ED_PUB", 0x42: "CMD_ED_SIGN", 0x43: "CMD_ED_WRAP", 0x50: "CMD_SHA512"}

if __name__ == "__main__":
    import random, hashlib
    from cryptography.hazmat.primitives.asymmetric import ec, ed25519, utils
    from cryptography.hazmat.primitives import hashes, serialization as ser
    random.seed(3)
    A = build(); code = A.link(); N = A.regs
    print(len(code), "instructions;", len(A.regs), "registers;", {k: v for k, v in A.entries.items()})
    def go(entry, **ins):
        regs, flag, steps = run(code, A.entries[entry], {N[k]: v for k, v in ins.items()})
        return (lambda n: regs.get(N[n], 0)), flag, steps
    # keygen / mul / ecdh / curve check
    d = random.randrange(1, P256_N)
    r, f, st = go("P256_KEYGEN", D=d)
    pn = ec.derive_private_key(d, ec.SECP256R1()).public_key().public_numbers()
    assert f == 0 and (r("OX"), r("OY")) == (pn.x, pn.y); print("P256_KEYGEN OK,", st, "instr")
    peer = ec.generate_private_key(ec.SECP256R1()); pp = peer.public_key().public_numbers()
    r, f, _ = go("P256_ECDH", D=d, QX=pp.x, QY=pp.y)
    shared = ec.derive_private_key(d, ec.SECP256R1()).exchange(ec.ECDH(), peer.public_key())
    assert f == 0 and r("OX").to_bytes(32, "big") == shared; print("P256_ECDH OK")
    r, f, _ = go("P256_ECDH", D=d, QX=pp.x, QY=(pp.y + 1) % P256_P); assert f == 1; print("ECDH rejects off-curve point OK")
    r, f, _ = go("P256_ONCURVE", PX=pp.x, PY=pp.y); assert f == 0
    r, f, _ = go("P256_ONCURVE", PX=pp.x, PY=pp.y ^ 1); assert f == 1; print("P256_ONCURVE OK")
    # sign (verified by cryptography) and verify (of cryptography's signatures)
    for _ in range(2):
        d = random.randrange(1, P256_N); k = random.randrange(1, P256_N); msg = os.urandom(40)
        z = int.from_bytes(hashlib.sha256(msg).digest(), "big")
        r, f, _ = go("P256_SIGN", D=d, Z=z, K=k); assert f == 0
        pk = ec.derive_private_key(d, ec.SECP256R1()).public_key()
        pk.verify(utils.encode_dss_signature(r("RR"), r("S")), msg, ec.ECDSA(hashes.SHA256()))
        pn = pk.public_numbers()
        rr, ff, _ = go("P256_VERIFY", Z=z, RR=r("RR"), S=r("S"), QX=pn.x, QY=pn.y); assert ff == 0
        rr, ff, _ = go("P256_VERIFY", Z=z ^ 1, RR=r("RR"), S=r("S"), QX=pn.x, QY=pn.y); assert ff == 1
    print("P256_SIGN verified by cryptography; P256_VERIFY accept/reject OK")
    # Ed25519
    seed = os.urandom(32); h = hashlib.sha512(seed).digest()
    a = int.from_bytes(h[:32], "little"); a &= (1 << 254) - 8; a |= 1 << 254
    r, f, st = go("ED_BASEMUL", K=a); assert f == 0
    enc = (r("OY") | ((r("OX") & 1) << 255)).to_bytes(32, "little")
    sk = ed25519.Ed25519PrivateKey.from_private_bytes(seed)
    pub = sk.public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw)
    assert enc == pub; print("ED_BASEMUL (pubkey) OK,", st, "instr")
    msg = os.urandom(33); prefix = h[32:]
    rh = hashlib.sha512(prefix + msg).digest()
    r1, f, _ = go("ED_REDUCE512", H0=int.from_bytes(rh[:32], "little"), H1=int.from_bytes(rh[32:], "little"))
    rl = r1("RR"); assert rl == int.from_bytes(rh, "little") % ED_L
    Rr, f, _ = go("ED_BASEMUL", K=rl); Renc = (Rr("OY") | ((Rr("OX") & 1) << 255)).to_bytes(32, "little")
    kh = hashlib.sha512(Renc + pub + msg).digest()
    r2, f, _ = go("ED_REDUCE512", H0=int.from_bytes(kh[:32], "little"), H1=int.from_bytes(kh[32:], "little"))
    r3, f, _ = go("ED_SIGN_S", RR=rl, KK=r2("RR"), AA=a)
    sig = Renc + r3("S").to_bytes(32, "little")
    assert sig == sk.sign(msg); print("Ed25519 signature identical to cryptography OK")
