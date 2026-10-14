#!/usr/bin/env python3
"""Hardware self-test of the ML-DSA bitstream. Signatures are verified by the PQClean C reference (lib/ via ref/pq/golden*)."""
import os, subprocess, sys, time
sys.path.insert(0, os.path.dirname(__file__))
from tro_accel import PqAccel, AccelError, AUTH_FAIL
HERE = os.path.dirname(os.path.abspath(__file__))
port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
a = PqAccel(port, 1_500_000, timeout=60)
fails = 0
def check(name, ok, extra=""):
    global fails
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {extra}", flush=True); fails += (not ok)
name, caps = a.ping(); check("ping", name == "TROACC01", f"caps={caps:#x}")
u = a.uid(); check("uid", len(u) == 16 and u == a.uid(), u.hex())
check("random", a.call(0x03) != a.call(0x03))
verify = os.path.join(HERE, "..", "ref", "pq", "verify")
def c_verify(ps, pk, sig, msg):
    r = subprocess.run([verify, str(ps), pk.hex(), sig.hex(), msg.hex()], capture_output=True, text=True)
    return r.stdout.strip() == "OK"
for ps in (44, 65, 87):
    t = time.time(); blob, pk = a.mldsa_generate(ps); dt = time.time() - t
    check(f"ML-DSA-{ps} keygen", len(blob) == a.blob_len(ps) and len(pk) == a.PK[ps], f"({dt:.2f}s)")
    for msg in (b"", b"hello", os.urandom(300)):
        t = time.time(); sig = a.mldsa_sign(ps, blob, msg); dt = time.time() - t
        check(f"ML-DSA-{ps} sign[{len(msg)}] verified by the C reference", len(sig) == a.SIG[ps] and c_verify(ps, pk, sig, msg), f"({dt:.2f}s)")
    bad = bytearray(blob); bad[40] ^= 1
    try: a.mldsa_sign(ps, bytes(bad), b"x"); rej = False
    except AccelError as e: rej = e.status == AUTH_FAIL
    check(f"ML-DSA-{ps} tampered blob rejected", rej)
print("\nALL PASS" if not fails else f"\n{fails} FAILED"); sys.exit(1 if fails else 0)
