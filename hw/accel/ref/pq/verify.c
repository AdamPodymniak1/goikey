// verify <44|65|87> <pk hex> <sig hex> <msg hex>  -> prints OK / FAIL (PQClean reference verification)
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "api_mldsa44.h"
#include "api_mldsa65.h"
#include "api_mldsa87.h"
static size_t unhex(const char *h, uint8_t *o) { size_t n = strlen(h) / 2; for (size_t i = 0; i < n; i++) { unsigned v; sscanf(h + 2 * i, "%2x", &v); o[i] = v; } return n; }
int main(int argc, char **argv) {
    static uint8_t pk[3000], sig[5000], msg[2000];
    int ps = atoi(argv[1]); unsigned pl = unhex(argv[2], pk); size_t sl = unhex(argv[3], sig), ml = argc > 4 ? unhex(argv[4], msg) : 0; (void)pl;
    int r = ps == 44 ? PQCLEAN_MLDSA44_CLEAN_crypto_sign_verify(sig, sl, msg, ml, pk) :
            ps == 65 ? PQCLEAN_MLDSA65_CLEAN_crypto_sign_verify(sig, sl, msg, ml, pk) : PQCLEAN_MLDSA87_CLEAN_crypto_sign_verify(sig, sl, msg, ml, pk);
    puts(r == 0 ? "OK" : "FAIL"); return r != 0;
}
