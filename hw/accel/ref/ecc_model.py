#!/usr/bin/env python3
"""Bit-exact Python model of the accelerator's modular engine + curve programs.

mont_mul() is the same word-serial CIOS (16-bit limbs) the RTL implements; the
curve code is written in terms of mul/add/sub exactly like the microprograms.
Run directly to cross-check against `cryptography` (P-256 / Ed25519).
"""
import os, sys, hashlib

W, S = 16, 16                     # limb bits, limbs per 256-bit operand
MASK = (1 << W) - 1
R = 1 << (W * S)

P256_P = 0xFFFFFFFF00000001000000000000000000000000FFFFFFFFFFFFFFFFFFFFFFFF
P256_N = 0xFFFFFFFF00000000FFFFFFFFFFFFFFFFBCE6FAADA7179E84F3B9CAC2FC632551
P256_B = 0x5AC635D8AA3A93E7B3EBBD55769886BC651D06B0CC53B0F63BCE3C3E27D2604B
P256_GX = 0x6B17D1F2E12C4247F8BCE6E563A440F277037D812DEB33A0F4A13945D898C296
P256_GY = 0x4FE342E2FE1A7F9B8EE7EB4A7C0F9E162BCE33576B315ECECBB6406837BF51F5
ED_P = (1 << 255) - 19
ED_L = (1 << 252) + 27742317777372353535851937790883648493
ED_D = (-121665 * pow(121666, -1, ED_P)) % ED_P
ED_BY = (4 * pow(5, -1, ED_P)) % ED_P

def n0inv(m):                      # -m^-1 mod 2^W
    return (-pow(m, -1, 1 << W)) % (1 << W)

def mont_mul(a, b, m):
    """CIOS word-serial Montgomery product a*b*R^-1 mod m (a,b < m)."""
    n0 = n0inv(m)
    t = [0] * (S + 2)
    A = [(a >> (W * i)) & MASK for i in range(S)]
    B = [(b >> (W * i)) & MASK for i in range(S)]
    N = [(m >> (W * i)) & MASK for i in range(S)]
    for i in range(S):
        c = 0
        for j in range(S):
            v = t[j] + A[i] * B[j] + c
            t[j], c = v & MASK, v >> W
        v = t[S] + c; t[S], t[S + 1] = v & MASK, v >> W
        mm = (t[0] * n0) & MASK
        v = t[0] + mm * N[0]; c = v >> W
        for j in range(1, S):
            v = t[j] + mm * N[j] + c
            t[j - 1], c = v & MASK, v >> W
        v = t[S] + c; t[S - 1], c = v & MASK, v >> W
        t[S] = t[S + 1] + c; t[S + 1] = 0
    r = sum(t[i] << (W * i) for i in range(S + 1))
    return r - m if r >= m else r

class Field:
    def __init__(self, m):
        self.m = m; self.R2 = (R * R) % m; self.one = R % m
    def to(self, x): return mont_mul(x % self.m, self.R2, self.m)
    def frm(self, x): return mont_mul(x, 1, self.m)
    def mul(self, a, b): return mont_mul(a, b, self.m)
    def add(self, a, b): s = a + b; return s - self.m if s >= self.m else s
    def sub(self, a, b): d = a - b; return d + self.m if d < 0 else d
    def inv(self, a):                       # Fermat, same square-and-multiply as the microprogram
        e = self.m - 2; r = self.one
        for i in range(255, -1, -1):
            r = self.mul(r, r)
            t = self.mul(r, a)
            if (e >> i) & 1: r = t
        return r

# ---------------- P-256: Renes-Costello-Batina complete formulas (a = -3) ----------------
def p256_add(F, b, P, Q):
    X1, Y1, Z1 = P; X2, Y2, Z2 = Q
    m, a, s = F.mul, F.add, F.sub
    t0 = m(X1, X2); t1 = m(Y1, Y2); t2 = m(Z1, Z2)
    t3 = a(X1, Y1); t4 = a(X2, Y2); t3 = m(t3, t4); t4 = a(t0, t1); t3 = s(t3, t4)
    t4 = a(Y1, Z1); X3 = a(Y2, Z2); t4 = m(t4, X3); X3 = a(t1, t2); t4 = s(t4, X3)
    X3 = a(X1, Z1); Y3 = a(X2, Z2); X3 = m(X3, Y3); Y3 = a(t0, t2); Y3 = s(X3, Y3)
    Z3 = m(b, t2); X3 = s(Y3, Z3); Z3 = a(X3, X3); X3 = a(X3, Z3); Z3 = s(t1, X3)
    X3 = a(t1, X3); Y3 = m(b, Y3); t1 = a(t2, t2); t2 = a(t1, t2); Y3 = s(Y3, t2)
    Y3 = s(Y3, t0); t1 = a(Y3, Y3); Y3 = a(t1, Y3); t1 = a(t0, t0); t0 = a(t1, t0)
    t0 = s(t0, t2); t1 = m(t4, Y3); t2 = m(t0, Y3); Y3 = m(X3, Z3); Y3 = a(Y3, t2)
    X3 = m(t3, X3); X3 = s(X3, t1); Z3 = m(t4, Z3); t1 = m(t3, t0); Z3 = a(Z3, t1)
    return (X3, Y3, Z3)

def p256_dbl(F, b, P):
    X, Y, Z = P
    m, a, s = F.mul, F.add, F.sub
    t0 = m(X, X); t1 = m(Y, Y); t2 = m(Z, Z); t3 = m(X, Y); t3 = a(t3, t3)
    Z3 = m(X, Z); Z3 = a(Z3, Z3); Y3 = m(b, t2); Y3 = s(Y3, Z3); X3 = a(Y3, Y3)
    Y3 = a(X3, Y3); X3 = s(t1, Y3); Y3 = a(t1, Y3); Y3 = m(X3, Y3); X3 = m(X3, t3)
    t3 = a(t2, t2); t2 = a(t2, t3); Z3 = m(b, Z3); Z3 = s(Z3, t2); Z3 = s(Z3, t0)
    t3 = a(Z3, Z3); Z3 = a(Z3, t3); t3 = a(t0, t0); t0 = a(t3, t0); t0 = s(t0, t2)
    t0 = m(t0, Z3); Y3 = a(Y3, t0); t0 = m(Y, Z); t0 = a(t0, t0); Z3 = m(t0, Z3)
    X3 = s(X3, Z3); Z3 = m(t0, t1); Z3 = a(Z3, Z3); Z3 = a(Z3, Z3)
    return (X3, Y3, Z3)

def sel(bit, a, b): return a if bit else b

def p256_scalar_mul(k, Px, Py, F=None):
    F = F or Field(P256_P); b = F.to(P256_B)
    P = (F.to(Px), F.to(Py), F.one)
    R_ = (0, F.one, 0)                         # identity (0:1:0)
    for i in range(255, -1, -1):
        R_ = p256_dbl(F, b, R_)
        T = p256_add(F, b, R_, P)
        bit = (k >> i) & 1
        R_ = tuple(sel(bit, T[j], R_[j]) for j in range(3))
    zi = F.inv(R_[2])
    return F.frm(F.mul(R_[0], zi)), F.frm(F.mul(R_[1], zi))

# ---------------- Ed25519: extended twisted Edwards, unified addition (a = -1) ----------------
def ed_add(F, d2, P, Q):
    X1, Y1, Z1, T1 = P; X2, Y2, Z2, T2 = Q
    m, a, s = F.mul, F.add, F.sub
    A = m(s(Y1, X1), s(Y2, X2)); B = m(a(Y1, X1), a(Y2, X2))
    C = m(m(T1, d2), T2); D = m(Z1, Z2); D = a(D, D)
    E = s(B, A); Fv = s(D, C); G = a(D, C); H = a(B, A)
    return (m(E, Fv), m(G, H), m(Fv, G), m(E, H))

def ed_scalar_mul(k, Bx, By, nbits=256):
    F = Field(ED_P); d2 = F.to((2 * ED_D) % ED_P)
    Pt = (F.to(Bx), F.to(By), F.one, F.to(Bx * By % ED_P))
    R_ = (0, F.one, F.one, 0)
    for i in range(nbits - 1, -1, -1):
        R_ = ed_add(F, d2, R_, R_)
        T = ed_add(F, d2, R_, Pt)
        bit = (k >> i) & 1
        R_ = tuple(sel(bit, T[j], R_[j]) for j in range(4))
    zi = F.inv(R_[2])
    return F.frm(F.mul(R_[0], zi)), F.frm(F.mul(R_[1], zi))

def ed_recover_x(y, sign):
    if y >= ED_P: return None
    x2 = (y * y - 1) * pow(ED_D * y * y + 1, -1, ED_P) % ED_P
    if x2 == 0: return None if sign else 0
    x = pow(x2, (ED_P + 3) // 8, ED_P)
    if (x * x - x2) % ED_P: x = x * pow(2, (ED_P - 1) // 4, ED_P) % ED_P
    if (x * x - x2) % ED_P: return None
    if (x & 1) != sign: x = ED_P - x
    return x
ED_BX = ed_recover_x(ED_BY, 0)

if __name__ == "__main__":
    import random
    from cryptography.hazmat.primitives.asymmetric import ec, ed25519
    from cryptography.hazmat.primitives import serialization as ser
    random.seed(5)
    # Montgomery multiplier vs python ints
    for m in (P256_P, P256_N, ED_P, ED_L):
        F = Field(m)
        for _ in range(200):
            a, b = random.randrange(m), random.randrange(m)
            assert F.frm(F.mul(F.to(a), F.to(b))) == a * b % m
        assert F.frm(F.inv(F.to(12345))) == pow(12345, -1, m)
    print("montgomery OK")
    # P-256 vs cryptography
    for _ in range(4):
        k = random.randrange(1, P256_N)
        pub = ec.derive_private_key(k, ec.SECP256R1()).public_key().public_numbers()
        assert p256_scalar_mul(k, P256_GX, P256_GY) == (pub.x, pub.y)
    print("p256 scalar mult OK")
    # Ed25519 vs cryptography (public key = clamp(sha512(seed)[:32]) * B)
    for _ in range(3):
        seed = os.urandom(32); h = hashlib.sha512(seed).digest()
        a = int.from_bytes(h[:32], "little"); a &= (1 << 254) - 8; a |= 1 << 254
        x, y = ed_scalar_mul(a, ED_BX, ED_BY)
        enc = (y | ((x & 1) << 255)).to_bytes(32, "little")
        ref = ed25519.Ed25519PrivateKey.from_private_bytes(seed).public_key().public_bytes(ser.Encoding.Raw, ser.PublicFormat.Raw)
        assert enc == ref
    print("ed25519 scalar mult OK")
