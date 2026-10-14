#ifndef CRYPTO_ACCEL_H
#define CRYPTO_ACCEL_H

#include <Arduino.h>

// Symmetric-crypto helpers that use the Tang Nano FPGA accelerator when it is attached and worthwhile,
// and compute on the ESP32 (mbedTLS) otherwise. They never fail just because the FPGA is missing:
//   * no FPGA / wrong bitstream loaded / transfer error  -> software result
//   * payload below the offload thresholds               -> software (the ESP32 has SHA/AES hardware, SPI round trips would cost more)
// Thresholds can be overridden with -D in platformio.ini.
#ifndef ACCEL_MIN_HASH_BYTES
#define ACCEL_MIN_HASH_BYTES   1024     // SHA-256 / HMAC-SHA256 message size
#endif
#ifndef ACCEL_MIN_AES_BYTES
#define ACCEL_MIN_AES_BYTES    256      // AES-CBC / AES-GCM payload size
#endif
#ifndef ACCEL_MIN_PBKDF2_ITER
#define ACCEL_MIN_PBKDF2_ITER  1000     // PBKDF2 iteration count
#endif

void accel_init();                      // probe the FPGA over SPI (safe when absent); call once at start-up
bool accel_present();                   // an accelerator answered recently
bool accel_has_rsa_keys();              // RSA-2048 keys can live in the FPGA (pq bitstream with RSA)
bool accel_has_asym_keys();             // asym bitstream loaded: FIDO credential keys can live in the FPGA

void accel_sha256(const uint8_t *data, size_t len, uint8_t out32[32]);
void accel_hmac_sha256(const uint8_t *key, size_t keyLen, const uint8_t *data, size_t len, uint8_t out32[32]);
bool accel_pbkdf2_sha256(const uint8_t *pw, size_t pwLen, const uint8_t *salt, size_t saltLen,
                         uint32_t iterations, uint8_t *out, size_t outLen);

// AES-256-CBC without padding (len % 16 == 0). `iv` is not modified.
bool accel_aes256_cbc(bool encrypt, const uint8_t key32[32], const uint8_t iv16[16], const uint8_t *in, size_t len, uint8_t *out);
// AES-256-GCM, 12-byte IV. decrypt returns false on authentication failure.
bool accel_aes256_gcm_encrypt(const uint8_t key32[32], const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                              const uint8_t *in, size_t len, uint8_t *out, uint8_t tag16[16]);
bool accel_aes256_gcm_decrypt(const uint8_t key32[32], const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                              const uint8_t *in, size_t len, const uint8_t tag16[16], uint8_t *out);

// Mix `len` bytes of FPGA TRNG output into `buf` by XOR (no-op when the FPGA is absent).
void accel_mix_random(uint8_t *buf, size_t len);

#endif
