// Deterministic randombytes for golden-vector generation (xorshift64*, seeded via pq_seed()).
#include <stdint.h>
#include <stddef.h>
static uint64_t st = 0x9E3779B97F4A7C15ULL;
void pq_seed(uint64_t s) { st = s ? s : 0x9E3779B97F4A7C15ULL; }
int PQCLEAN_randombytes(uint8_t *buf, size_t n) {
    for (size_t i = 0; i < n; i++) { st ^= st >> 12; st ^= st << 25; st ^= st >> 27; buf[i] = (uint8_t)((st * 0x2545F4914F6CDD1DULL) >> 56); }
    return 0;
}
