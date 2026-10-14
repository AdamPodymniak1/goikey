#include "CryptoAccel.h"
#include "FpgaAccel.h"
#include "mbedtls/md.h"
#include "mbedtls/aes.h"
#include "mbedtls/gcm.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/sha256.h"
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>

static SemaphoreHandle_t g_mx = nullptr;
struct Lock {
    Lock()  { if (g_mx) xSemaphoreTakeRecursive(g_mx, portMAX_DELAY); }
    ~Lock() { if (g_mx) xSemaphoreGiveRecursive(g_mx); }
};

void accel_init() {
    if (!g_mx) g_mx = xSemaphoreCreateRecursiveMutex();
    Lock l;
    bool ok = fpga_init_spi();
    Serial.printf("[ACCEL] FPGA %s", ok ? "detected" : "not detected - computing on the ESP32");
    if (ok) Serial.printf(" (caps %08x: %s%s%s%s%s)", (unsigned)fpga_caps(), fpga_has_sym() ? "sha256/hmac/pbkdf2 " : "", fpga_has_aes() ? "aes " : "",
                          fpga_has_asym() ? "p256/ed25519 " : "", fpga_has_pq() ? "ml-dsa " : "", fpga_has_rsa() ? "rsa" : "");
    Serial.println();
}
bool accel_present() { Lock l; return fpga_available(); }
bool accel_has_asym_keys() { Lock l; return fpga_has_asym(); }
bool accel_has_rsa_keys() { Lock l; return fpga_has_rsa(); }

// ------------------------------------------------------------------ hashing
void accel_sha256(const uint8_t *data, size_t len, uint8_t out32[32]) {
    if (len >= ACCEL_MIN_HASH_BYTES) {
        Lock l;
        if (fpga_has_sym() && fpga_sha256(data, len, out32)) return;
    }
    mbedtls_sha256(data, len, out32, 0);
}

void accel_hmac_sha256(const uint8_t *key, size_t keyLen, const uint8_t *data, size_t len, uint8_t out32[32]) {
    if (len >= ACCEL_MIN_HASH_BYTES) {
        uint8_t kh[32];
        const uint8_t *k = key; size_t kl = keyLen;
        if (kl > 64) { mbedtls_sha256(key, keyLen, kh, 0); k = kh; kl = 32; }       // RFC 2104
        Lock l;
        if (fpga_has_sym() && fpga_hmac_sha256(k, kl, data, len, out32)) return;
    }
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
    mbedtls_md_hmac_starts(&ctx, key, keyLen);
    mbedtls_md_hmac_update(&ctx, data, len);
    mbedtls_md_hmac_finish(&ctx, out32);
    mbedtls_md_free(&ctx);
}

bool accel_pbkdf2_sha256(const uint8_t *pw, size_t pwLen, const uint8_t *salt, size_t saltLen,
                         uint32_t iterations, uint8_t *out, size_t outLen) {
    if (iterations >= ACCEL_MIN_PBKDF2_ITER) {
        uint8_t ph[32];
        const uint8_t *p = pw; size_t pl = pwLen;
        if (pl > 64) { mbedtls_sha256(pw, pwLen, ph, 0); p = ph; pl = 32; }           // RFC 2104 key pre-hash
        Lock l;
        if (fpga_has_sym() && fpga_pbkdf2_sha256(p, pl, salt, saltLen, iterations, out, outLen)) return true;
    }
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 1);
    int rc = mbedtls_pkcs5_pbkdf2_hmac(&ctx, pw, pwLen, salt, saltLen, iterations, outLen, out);
    mbedtls_md_free(&ctx);
    return rc == 0;
}

// ------------------------------------------------------------------ AES
bool accel_aes256_cbc(bool encrypt, const uint8_t key32[32], const uint8_t iv16[16], const uint8_t *in, size_t len, uint8_t *out) {
    if (len == 0 || len % 16 != 0) return false;
    if (len >= ACCEL_MIN_AES_BYTES && len <= 7900) {
        Lock l;
        if (fpga_has_aes() && fpga_aes_set_key(key32) && fpga_aes_cbc(encrypt, iv16, in, len, out)) return true;
    }
    mbedtls_aes_context aes; mbedtls_aes_init(&aes);
    int rc = encrypt ? mbedtls_aes_setkey_enc(&aes, key32, 256) : mbedtls_aes_setkey_dec(&aes, key32, 256);
    uint8_t iv[16]; memcpy(iv, iv16, 16);
    if (rc == 0) rc = mbedtls_aes_crypt_cbc(&aes, encrypt ? MBEDTLS_AES_ENCRYPT : MBEDTLS_AES_DECRYPT, len, iv, in, out);
    mbedtls_aes_free(&aes);
    return rc == 0;
}

bool accel_aes256_gcm_encrypt(const uint8_t key32[32], const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                              const uint8_t *in, size_t len, uint8_t *out, uint8_t tag16[16]) {
    if (len >= ACCEL_MIN_AES_BYTES && len + aadLen <= 7900) {
        Lock l;
        if (fpga_has_aes() && fpga_aes_set_key(key32) && fpga_aes_gcm_encrypt(iv12, aad, aadLen, in, len, out, tag16)) return true;
    }
    mbedtls_gcm_context gcm; mbedtls_gcm_init(&gcm);
    int rc = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, key32, 256);
    if (rc == 0) rc = mbedtls_gcm_crypt_and_tag(&gcm, MBEDTLS_GCM_ENCRYPT, len, iv12, 12, aad, aadLen, in, out, 16, tag16);
    mbedtls_gcm_free(&gcm);
    return rc == 0;
}

bool accel_aes256_gcm_decrypt(const uint8_t key32[32], const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                              const uint8_t *in, size_t len, const uint8_t tag16[16], uint8_t *out) {
    if (len >= ACCEL_MIN_AES_BYTES && len + aadLen <= 7900) {
        Lock l;
        if (fpga_has_aes() && fpga_aes_set_key(key32)) {
            if (fpga_aes_gcm_decrypt(iv12, aad, aadLen, in, len, tag16, out)) return true;
            if (fpga_last_status() == FPGA_AUTH_FAIL) return false;               // authentic failure, not a transport problem
        }
    }
    mbedtls_gcm_context gcm; mbedtls_gcm_init(&gcm);
    int rc = mbedtls_gcm_setkey(&gcm, MBEDTLS_CIPHER_ID_AES, key32, 256);
    if (rc == 0) rc = mbedtls_gcm_auth_decrypt(&gcm, len, iv12, 12, aad, aadLen, tag16, 16, in, out);
    mbedtls_gcm_free(&gcm);
    return rc == 0;
}

void accel_mix_random(uint8_t *buf, size_t len) {
    uint8_t *tmp = (uint8_t *)malloc(len);
    if (!tmp) return;
    {
        Lock l;
        if (fpga_available() && fpga_fill_random(tmp, len)) for (size_t i = 0; i < len; i++) buf[i] ^= tmp[i];
    }
    memset(tmp, 0, len); free(tmp);
}
