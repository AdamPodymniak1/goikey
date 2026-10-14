#ifndef FPGA_ACCEL_H
#define FPGA_ACCEL_H

// Driver for the Tang Nano 20k crypto accelerator (see hw/accel/README.md).
//
// Transport: SPI (ESP32 = master, mode 0, <= 4 MHz) on the firmware; a POSIX UART transport exists for host tests.
// Framing:   A5 | cmd | len(2 LE) | payload | crc16(2 LE)   ->   5A | status | len(2 LE) | payload | crc16(2 LE)
//
// The FPGA is optional: fpga_init_*() reports whether it answered; every wrapper returns false when it is absent
// or fails, and the caller (CryptoAccel.cpp) then computes on the ESP32 instead. After a failure the device is
// re-probed at most every few seconds so a missing board costs almost nothing.
//
// Two bitstreams exist (one runs at a time): "asym" (P-256 / Ed25519 / SHA-512 with device-wrapped keys) and
// "sym" (SHA-256 / HMAC / PBKDF2 / AES-CBC / AES-GCM). fpga_has_sym()/fpga_has_aes()/fpga_has_asym()/fpga_has_pq()/fpga_has_rsa() tell what is loaded.

#include <stddef.h>
#include <stdint.h>

enum FpgaStatus : uint8_t {
    FPGA_OK = 0, FPGA_BAD_CMD = 1, FPGA_BAD_LEN = 2, FPGA_BAD_CRC = 3, FPGA_AUTH_FAIL = 4,
    FPGA_ERR = 5, FPGA_BAD_PARAM = 6, FPGA_NO_KEY = 7,
    FPGA_IO_TIMEOUT = 0xF0, FPGA_IO_CRC = 0xF1, FPGA_ABSENT = 0xF2
};

static const size_t FPGA_BLOB_LEN = 64;
static const uint32_t FPGA_CAPS_SYM  = 0x00000007;   // SHA-256 / HMAC / PBKDF2
static const uint32_t FPGA_CAPS_AES  = 0x00000008;   // AES-256 CBC / GCM
static const uint32_t FPGA_CAPS_ASYM = 0x000000F0;
static const uint32_t FPGA_CAPS_PQ   = 0x00000300;
static const uint32_t FPGA_CAPS_RSA  = 0x00000400;

#ifdef ARDUINO
// SPI wiring (ESP32-S3 DevKitC-1): override with -D FPGA_PIN_SCK=... in platformio.ini
#ifndef FPGA_PIN_SCK
#define FPGA_PIN_SCK   14
#endif
#ifndef FPGA_PIN_MOSI
#define FPGA_PIN_MOSI  15
#endif
#ifndef FPGA_PIN_MISO
#define FPGA_PIN_MISO  21
#endif
#ifndef FPGA_PIN_CS
#define FPGA_PIN_CS    18
#endif
bool fpga_init_spi(int sck = FPGA_PIN_SCK, int miso = FPGA_PIN_MISO, int mosi = FPGA_PIN_MOSI, int cs = FPGA_PIN_CS,
                   uint32_t hz = 4000000);
#else
bool fpga_init_uart(const char *device, int baud = 1500000);      // host tests
#endif

bool fpga_available();                  // true if the accelerator answers (re-probes rarely after a failure)
uint32_t fpga_caps();
bool fpga_has_sym();                   // SHA-256 / HMAC / PBKDF2
bool fpga_has_aes();                   // AES-256 CBC / GCM
bool fpga_has_asym();
bool fpga_has_pq();
bool fpga_has_rsa();
FpgaStatus fpga_last_status();

// ---- info / entropy ----
bool fpga_uid(uint8_t uid16[16]);
bool fpga_fill_random(uint8_t *out, size_t len);

// ---- P-256 (asym). Public key = X||Y (64 bytes), signature = r||s (64 bytes) ----
bool fpga_p256_genkey(uint8_t blobOut[FPGA_BLOB_LEN], uint8_t pubOut64[64]);
bool fpga_p256_public(const uint8_t blob[FPGA_BLOB_LEN], uint8_t pubOut64[64]);
bool fpga_p256_sign(const uint8_t blob[FPGA_BLOB_LEN], const uint8_t digest32[32], uint8_t sigOut64[64]);
bool fpga_p256_ecdh(const uint8_t blob[FPGA_BLOB_LEN], const uint8_t peerPub64[64], uint8_t secretOut32[32]);
bool fpga_p256_verify(const uint8_t digest32[32], const uint8_t sig64[64], const uint8_t pub64[64]);
bool fpga_p256_import(const uint8_t raw32[32], uint8_t blobOut[FPGA_BLOB_LEN]);

// ---- Ed25519 (asym) ----
bool fpga_ed25519_genkey(uint8_t blobOut[FPGA_BLOB_LEN], uint8_t pubOut32[32]);
bool fpga_ed25519_public(const uint8_t blob[FPGA_BLOB_LEN], uint8_t pubOut32[32]);
bool fpga_ed25519_sign(const uint8_t blob[FPGA_BLOB_LEN], const uint8_t *msg, size_t len, uint8_t sigOut64[64]);
bool fpga_ed25519_import(const uint8_t seed32[32], uint8_t blobOut[FPGA_BLOB_LEN]);

// ---- ML-DSA (pq bitstream) - parameter set 44, 65 or 87. The private key is a wrapped blob of (secret key + 32) bytes ----
size_t fpga_mldsa_blob_len(int ps);      // 2592 / 4064 / 4928, 0 for an unknown set
bool fpga_mldsa_genkey(int ps, uint8_t *blobOut, uint8_t *pubOut);     // blobOut: fpga_mldsa_blob_len(ps) bytes, pubOut: 1312 / 1952 / 2592 bytes
// RSA-2048 (e = 65537, CRT private key wrapped under the device master key). Keygen takes tens of seconds (prime search).
static const size_t FPGA_RSA_BLOB_LEN = 672;
bool fpga_rsa_genkey(uint8_t blobOut[FPGA_RSA_BLOB_LEN], uint8_t nOut256[256]);
bool fpga_rsa_public(const uint8_t blob[FPGA_RSA_BLOB_LEN], uint8_t nOut256[256]);
bool fpga_rsa_sign_sha256(const uint8_t blob[FPGA_RSA_BLOB_LEN], const uint8_t digest32[32], uint8_t sigOut256[256]);   // RSASSA-PKCS1-v1_5
bool fpga_mldsa_sign(int ps, const uint8_t *blob, const uint8_t *msg, size_t msgLen, uint8_t *sigOut, size_t *sigLen);

// ---- hashing ----
bool fpga_sha512(const uint8_t *data, size_t len, uint8_t out64[64]);                               // asym
bool fpga_sha256(const uint8_t *data, size_t len, uint8_t out32[32]);                               // sym
bool fpga_hmac_sha256(const uint8_t *key, size_t keyLen, const uint8_t *data, size_t len, uint8_t out32[32]);  // sym, key <= 64
bool fpga_pbkdf2_sha256(const uint8_t *pw, size_t pwLen, const uint8_t *salt, size_t saltLen,
                        uint32_t iterations, uint8_t *out, size_t outLen);                          // sym, pw <= 64

// ---- AES-256 (sym). Payload per call <= ~8000 bytes ----
bool fpga_aes_set_key(const uint8_t key32[32]);
bool fpga_aes_cbc(bool encrypt, const uint8_t iv16[16], const uint8_t *in, size_t len, uint8_t *out);   // len % 16 == 0
bool fpga_aes_gcm_encrypt(const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                          const uint8_t *in, size_t len, uint8_t *out, uint8_t tag16[16]);
bool fpga_aes_gcm_decrypt(const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                          const uint8_t *in, size_t len, const uint8_t tag16[16], uint8_t *out);     // false on auth failure

#endif
