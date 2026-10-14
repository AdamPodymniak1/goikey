#!/usr/bin/env python3
"""Reference semantics of the RSA big-number unit (1024-bit registers) used by the interpreter and as RTL oracle."""
import hashlib
W = 16; S = 64; R = 1 << 1024; MASK = (1 << 1024) - 1
def n0inv(m):                       # -m^-1 mod 2^16 (m odd)
    return (-pow(m, -1, 1 << W)) % (1 << W)
def mont_mul(a, b, m):
    """CIOS Montgomery product a*b*R^-1 mod m, 16-bit limbs, 64 limbs, final conditional subtract."""
    n0 = n0inv(m); t = [0] * (S + 2)
    A = [(a >> (16 * i)) & 0xFFFF for i in range(S)]; B = [(b >> (16 * i)) & 0xFFFF for i in range(S)]; N = [(m >> (16 * i)) & 0xFFFF for i in range(S)]
    for i in range(S):
        c = 0
        for j in range(S):
            v = t[j] + A[i] * B[j] + c; t[j], c = v & 0xFFFF, v >> 16
        v = t[S] + c; t[S], t[S + 1] = v & 0xFFFF, v >> 16
        mm = (t[0] * n0) & 0xFFFF
        v = t[0] + mm * N[0]; c = v >> 16
        for j in range(1, S):
            v = t[j] + mm * N[j] + c; t[j - 1], c = v & 0xFFFF, v >> 16
        v = t[S] + c; t[S - 1], c = v & 0xFFFF, v >> 16
        t[S] = t[S + 1] + c; t[S + 1] = 0
    r = sum(t[i] << (16 * i) for i in range(S + 1))
    return r - m if r >= m else r
SMALL_PRIMES = [p for p in range(3, 1024, 2) if all(p % q for q in range(3, int(p ** .5) + 1, 2))]
