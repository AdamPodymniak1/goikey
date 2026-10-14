#!/usr/bin/env bash
# Build the PQClean ML-DSA reference helpers used by the testbench generators (run from anywhere, needs gcc):
#   ref/pq/golden <44|65|87> <seed> <msg-hex>   keypair + signature with deterministic randomness
#   ref/pq/verify <44|65|87> <pk> <sig> <msg>   PQClean verification (prints OK / FAIL)
# lib/commons/randombytes.c is the ESP32 one, so rng_stub.c replaces it here.
set -euo pipefail
ROOT="$(cd "$(dirname "${BASH_SOURCE[0]}")/../../../.." && pwd)"; HERE="$ROOT/hw/accel/ref/pq"
SRC="$(ls "$ROOT"/lib/ML-DSA44/*.c "$ROOT"/lib/ML-DSA65/*.c "$ROOT"/lib/ML-DSA87/*.c) $ROOT/lib/commons/fips202.c $ROOT/lib/commons/sha2.c"
INC="-I$ROOT/lib/commons -I$ROOT/lib/ML-DSA44 -I$ROOT/lib/ML-DSA65 -I$ROOT/lib/ML-DSA87"
for t in golden verify; do ${CC:-gcc} -O2 $INC "$HERE/$t.c" "$HERE/rng_stub.c" $SRC -o "$HERE/$t"; done
echo "built $HERE/golden and $HERE/verify"
