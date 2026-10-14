// Prints keypair + signature for one ML-DSA parameter set with deterministic randomness.
//   golden <44|65|87> <seed> <msg-hex>
#include <stdio.h>
#include <stdlib.h>
#include <string.h>
#include <stdint.h>
#include "api_mldsa44.h"
#include "api_mldsa65.h"
#include "api_mldsa87.h"
void pq_seed(uint64_t s);
static void hex(const char *n, const uint8_t *b, size_t l) { printf("%s=", n); for (size_t i = 0; i < l; i++) printf("%02x", b[i]); printf("\n"); }
int main(int argc, char **argv) {
    int ps = atoi(argv[1]); pq_seed(strtoull(argv[2], 0, 10));
    uint8_t msg[256]; size_t ml = strlen(argv[3]) / 2;
    for (size_t i = 0; i < ml; i++) { unsigned v; sscanf(argv[3] + 2 * i, "%2x", &v); msg[i] = v; }
    static uint8_t pk[3000], sk[5000], sig[5000]; size_t sl = 0;
#define RUN(P) do { PQCLEAN_MLDSA##P##_CLEAN_crypto_sign_keypair(pk, sk); \
    PQCLEAN_MLDSA##P##_CLEAN_crypto_sign_signature(sig, &sl, msg, ml, sk); \
    hex("pk", pk, PQCLEAN_MLDSA##P##_CLEAN_CRYPTO_PUBLICKEYBYTES); hex("sk", sk, PQCLEAN_MLDSA##P##_CLEAN_CRYPTO_SECRETKEYBYTES); \
    hex("sig", sig, sl); \
    printf("verify=%d\n", PQCLEAN_MLDSA##P##_CLEAN_crypto_sign_verify(sig, sl, msg, ml, pk)); } while (0)
    if (ps == 44) RUN(44); else if (ps == 65) RUN(65); else RUN(87);
    return 0;
}
