#!/usr/bin/env python3
"""Hardware test for the Tang Nano 20k Root of Trust.

Captures the UART reporter output and checks:
  - UID is well-formed, constant, and equals the build's uid.hex (if present)
  - every RND line is unique (no repeats / stuck output)
  - monobit, runs, byte chi-square and serial-correlation statistics of the TRNG

Usage: test_trng.py [port] [seconds]     (stdlib only)
"""
import math, os, re, sys, time, termios

port = sys.argv[1] if len(sys.argv) > 1 else "/dev/ttyUSB1"
secs = float(sys.argv[2]) if len(sys.argv) > 2 else 100

fd = os.open(port, os.O_RDWR | os.O_NOCTTY)
a = termios.tcgetattr(fd)
a[0] = a[1] = a[3] = 0
a[2] = termios.CS8 | termios.CREAD | termios.CLOCAL
a[4] = a[5] = termios.B115200
termios.tcsetattr(fd, termios.TCSANOW, a)
termios.tcflush(fd, termios.TCIFLUSH)

buf, end = b"", time.time() + secs
while time.time() < end:
    buf += os.read(fd, 4096)
text = buf.decode("ascii", "replace")

uids = re.findall(r"TRO UID: ([0-9a-f]{32})\r\n", text)
rnds = re.findall(r"TRO RND: ([0-9a-f]{64})\r\n", text)
fails = []
def check(name, ok, detail=""):
    print(f"[{'PASS' if ok else 'FAIL'}] {name} {detail}")
    if not ok: fails.append(name)

check("captured lines", len(rnds) >= 20, f"({len(rnds)} RND, {len(uids)} UID)")
check("UID constant", len(set(uids)) == 1, uids[0] if uids else "")
uidf = os.path.join(os.path.dirname(__file__), "build", "uid.hex")
if os.path.exists(uidf) and uids:
    check("UID == build/uid.hex", open(uidf).read().strip() == uids[0])
check("RND lines unique", len(set(rnds)) == len(rnds))

data = bytes.fromhex("".join(rnds))
bits = "".join(f"{b:08b}" for b in data)
n = len(bits)
print(f"\n{len(data)} bytes / {n} bits analysed")

ones = bits.count("1")
z = abs(ones - n / 2) / math.sqrt(n / 4)
check("monobit", z < 4, f"ones={ones/n:.4f} z={z:.2f}")

runs = 1 + sum(bits[i] != bits[i+1] for i in range(n-1))
pi = ones / n
exp = 2 * n * pi * (1 - pi)
zr = abs(runs - exp) / (2 * math.sqrt(2 * n) * pi * (1 - pi))
check("runs", zr < 4, f"runs={runs} expected~{exp:.0f} z={zr:.2f}")

cnt = [0] * 256
for b in data: cnt[b] += 1
e = len(data) / 256
chi = sum((c - e) ** 2 / e for c in cnt)
check("byte chi-square", 255 - 5 * math.sqrt(510) < chi < 255 + 5 * math.sqrt(510), f"chi2={chi:.1f} (df=255)")

x = [int(c) for c in bits]
m = sum(x) / n
corr = sum((x[i]-m)*(x[i+1]-m) for i in range(n-1)) / sum((v-m)**2 for v in x)
check("serial correlation", abs(corr) < 4 / math.sqrt(n), f"r={corr:+.4f}")

# min-entropy estimate (most-common-byte), informational
pmax = max(cnt) / len(data)
print(f"[info] most-common-byte min-entropy ≈ {-math.log2(pmax):.2f} bits/byte")

print("\nRESULT:", "FAIL: " + ", ".join(fails) if fails else "ALL PASS")
sys.exit(1 if fails else 0)
