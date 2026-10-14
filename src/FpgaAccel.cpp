#include "FpgaAccel.h"
#include <string.h>
#include <stdlib.h>

#ifdef ARDUINO
#include <Arduino.h>
#include <SPI.h>
#include <freertos/FreeRTOS.h>
#include <freertos/semphr.h>
static SemaphoreHandle_t g_tp_mx = nullptr;                       // serialises whole request/response exchanges between tasks
struct TpLock {
    TpLock()  { if (g_tp_mx) xSemaphoreTakeRecursive(g_tp_mx, portMAX_DELAY); }
    ~TpLock() { if (g_tp_mx) xSemaphoreGiveRecursive(g_tp_mx); }
};
static SPIClass g_spi(HSPI);
static int g_cs = -1;
static uint32_t g_hz = 4000000;
static uint32_t now_ms() { return millis(); }
static void sleep_ms(uint32_t ms) { delay(ms); }
#else
#include <fcntl.h>
#include <termios.h>
#include <unistd.h>
#include <time.h>
struct TpLock {};
static int g_fd = -1;
static uint32_t now_ms() { timespec t; clock_gettime(CLOCK_MONOTONIC, &t); return (uint32_t)(t.tv_sec * 1000UL + t.tv_nsec / 1000000UL); }

#endif

static bool g_tp_ready = false;      // transport initialised
static bool g_ok = false;            // device answered the last probe / call
static uint32_t g_retry_at = 0;      // earliest time of the next probe after a failure
static uint32_t g_caps = 0;
static FpgaStatus g_last = FPGA_ABSENT;
static const size_t FPGA_MAX_PAYLOAD = 8000;

// ---------------------------------------------------------------- CRC
static uint16_t crc16(const uint8_t *d, size_t n, uint16_t c = 0xFFFF) {
    for (size_t i = 0; i < n; i++) {
        c ^= (uint16_t)d[i] << 8;
        for (int b = 0; b < 8; b++) c = (c & 0x8000) ? (uint16_t)((c << 1) ^ 0x1021) : (uint16_t)(c << 1);
    }
    return c;
}

// ---------------------------------------------------------------- transports
#ifdef ARDUINO
static uint8_t g_left[64]; static size_t g_left_n = 0, g_left_p = 0;     // bytes read past the start byte (SPI chunking)
#else
static size_t g_left_n = 0, g_left_p = 0;
#endif

#ifdef ARDUINO
static void spi_xfer(const uint8_t *tx, uint8_t *rx, size_t n) {
    g_spi.beginTransaction(SPISettings(g_hz, MSBFIRST, SPI_MODE0));
    digitalWrite(g_cs, LOW);
    if (tx) g_spi.transferBytes(tx, rx, n);
    else { static uint8_t zeros[64]; size_t o = 0; while (o < n) { size_t c = min(n - o, sizeof zeros); g_spi.transferBytes(zeros, rx ? rx + o : nullptr, c); o += c; } }
    digitalWrite(g_cs, HIGH);
    g_spi.endTransaction();
}
static bool tp_write(const uint8_t *b, size_t n) {
    // chunk so the 4-byte-aligned DMA buffers stay small
    size_t o = 0;
    g_spi.beginTransaction(SPISettings(g_hz, MSBFIRST, SPI_MODE0));
    digitalWrite(g_cs, LOW);
    while (o < n) { size_t c = min(n - o, (size_t)2048); g_spi.transferBytes((uint8_t *)b + o, nullptr, c); o += c; }
    digitalWrite(g_cs, HIGH);
    g_spi.endTransaction();
    g_left_n = g_left_p = 0;
    return true;
}
// Clock filler bytes until the start byte 0x5A has been seen.
static bool tp_wait_sof(uint32_t timeoutMs) {
    uint32_t t0 = now_ms(); uint8_t buf[8]; unsigned spins = 0;
    for (;;) {
        spi_xfer(nullptr, buf, sizeof buf);
        for (size_t i = 0; i < sizeof buf; i++) if (buf[i] == 0x5A) {
            g_left_n = sizeof buf - (i + 1); g_left_p = 0; memcpy(g_left, buf + i + 1, g_left_n); return true;
        }
        if (now_ms() - t0 > timeoutMs) return false;
        if (++spins > 40) sleep_ms(1);
    }
}
static bool tp_read(uint8_t *dst, size_t n, uint32_t) {
    size_t o = 0;
    while (o < n && g_left_p < g_left_n) dst[o++] = g_left[g_left_p++];
    while (o < n) { size_t c = min(n - o, (size_t)2048); spi_xfer(nullptr, dst + o, c); o += c; }
    return true;
}
bool fpga_init_spi(int sck, int miso, int mosi, int cs, uint32_t hz) {
    g_cs = cs; g_hz = hz;
    if (!g_tp_mx) g_tp_mx = xSemaphoreCreateRecursiveMutex();
    pinMode(cs, OUTPUT); digitalWrite(cs, HIGH);
    g_spi.begin(sck, miso, mosi, -1);
    g_tp_ready = true; g_ok = false; g_retry_at = 0;
    return fpga_available();
}
#else
bool fpga_init_uart(const char *device, int baud) {
    g_fd = open(device, O_RDWR | O_NOCTTY);
    if (g_fd < 0) return false;
    termios t; tcgetattr(g_fd, &t); cfmakeraw(&t);
    speed_t sp = (baud == 115200) ? B115200 : B1500000;
    cfsetispeed(&t, sp); cfsetospeed(&t, sp); t.c_cflag |= CLOCAL | CREAD; t.c_cc[VMIN] = 0; t.c_cc[VTIME] = 1;
    tcsetattr(g_fd, TCSANOW, &t); tcflush(g_fd, TCIOFLUSH);
    g_tp_ready = true; g_ok = false; g_retry_at = 0;
    return fpga_available();
}
static bool tp_write(const uint8_t *b, size_t n) { tcflush(g_fd, TCIFLUSH); g_left_n = g_left_p = 0; return write(g_fd, b, n) == (ssize_t)n; }
static bool tp_read(uint8_t *dst, size_t n, uint32_t timeoutMs) {
    uint32_t t0 = now_ms(); size_t o = 0;
    while (o < n) {
        ssize_t r = read(g_fd, dst + o, n - o);
        if (r > 0) o += r; else if (now_ms() - t0 > timeoutMs) return false;
    }
    return true;
}
static bool tp_wait_sof(uint32_t timeoutMs) {
    uint8_t b; uint32_t t0 = now_ms();
    while (now_ms() - t0 <= timeoutMs) { if (read(g_fd, &b, 1) == 1 && b == 0x5A) return true; }
    return false;
}
#endif

// ---------------------------------------------------------------- one request / response
static bool io_fail(FpgaStatus s) { g_last = s; g_ok = false; g_retry_at = now_ms() + 3000; return false; }

static bool call_raw(uint8_t cmd, const uint8_t *pl, size_t plLen, uint8_t *rsp, size_t rspMax, size_t *rspLen, uint32_t timeoutMs) {
    TpLock lock_;
    if (!g_tp_ready || plLen > FPGA_MAX_PAYLOAD) { g_last = FPGA_ABSENT; return false; }
    uint8_t *req = (uint8_t *)malloc(plLen + 6);
    if (!req) return false;
    req[0] = 0xA5; req[1] = cmd; req[2] = plLen & 0xFF; req[3] = plLen >> 8;
    if (plLen) memcpy(req + 4, pl, plLen);
    uint16_t c = crc16(req + 1, 3 + plLen);
    req[4 + plLen] = c & 0xFF; req[5 + plLen] = c >> 8;
    bool w = tp_write(req, plLen + 6);
    free(req);
    if (!w) return io_fail(FPGA_IO_TIMEOUT);
    if (!tp_wait_sof(timeoutMs)) return io_fail(FPGA_IO_TIMEOUT);
    uint8_t h[3];
    if (!tp_read(h, 3, timeoutMs)) return io_fail(FPGA_IO_TIMEOUT);
    size_t n = h[1] | ((size_t)h[2] << 8);
    if (n > rspMax) { g_last = FPGA_BAD_LEN; return false; }
    if (n && !tp_read(rsp, n, timeoutMs)) return io_fail(FPGA_IO_TIMEOUT);
    uint8_t cc[2];
    if (!tp_read(cc, 2, timeoutMs)) return io_fail(FPGA_IO_TIMEOUT);
    uint16_t rc = crc16(h, 3); rc = crc16(rsp, n, rc);
    if (rc != (uint16_t)(cc[0] | (cc[1] << 8))) return io_fail(FPGA_IO_CRC);
    g_last = (FpgaStatus)h[0];
    if (rspLen) *rspLen = n;
    return h[0] == FPGA_OK;
}

// Guarded call: returns false immediately when no FPGA is present.
static bool call(uint8_t cmd, const uint8_t *pl, size_t plLen, uint8_t *rsp, size_t rspMax, size_t *rspLen, uint32_t timeoutMs = 3000) {
    if (!fpga_available()) { g_last = FPGA_ABSENT; return false; }
    return call_raw(cmd, pl, plLen, rsp, rspMax, rspLen, timeoutMs);
}
static bool callExact(uint8_t cmd, const uint8_t *pl, size_t plLen, uint8_t *rsp, size_t want, uint32_t timeoutMs = 3000) {
    size_t n = 0;
    return call(cmd, pl, plLen, rsp, want, &n, timeoutMs) && n == want;
}

bool fpga_available() {
    if (!g_tp_ready) return false;
    if (g_ok) return true;
    if (now_ms() < g_retry_at) return false;
    uint8_t r[12]; size_t n = 0;
    bool ok = call_raw(0x01, nullptr, 0, r, sizeof r, &n, 60) && n == 12 && memcmp(r, "TROACC01", 8) == 0;
    if (ok) {
        g_caps = ((uint32_t)r[8] << 24) | ((uint32_t)r[9] << 16) | ((uint32_t)r[10] << 8) | r[11];
        g_ok = true;
    } else { g_ok = false; g_retry_at = now_ms() + 5000; g_last = FPGA_ABSENT; }
    return g_ok;
}
uint32_t fpga_caps() { return fpga_available() ? g_caps : 0; }
bool fpga_has_sym()  { return (fpga_caps() & FPGA_CAPS_SYM) == FPGA_CAPS_SYM; }
bool fpga_has_aes()  { return (fpga_caps() & FPGA_CAPS_AES) != 0; }
bool fpga_has_asym() { return (fpga_caps() & FPGA_CAPS_ASYM) != 0; }
bool fpga_has_pq()   { return (fpga_caps() & FPGA_CAPS_PQ) != 0; }
bool fpga_has_rsa()  { return (fpga_caps() & FPGA_CAPS_RSA) == FPGA_CAPS_RSA; }
FpgaStatus fpga_last_status() { return g_last; }

// ---------------------------------------------------------------- info
bool fpga_uid(uint8_t uid16[16]) { return callExact(0x02, nullptr, 0, uid16, 16); }
bool fpga_fill_random(uint8_t *out, size_t len) {
    uint8_t r[32];
    while (len) {
        // sym-only bitstream: payload = byte count (LE16); any bitstream with asym/pq units: no payload, always 32 bytes
        static const uint8_t n32[2] = {32, 0};
        bool symOnly = fpga_has_sym() && !fpga_has_asym() && !fpga_has_pq();
        if (!(symOnly ? callExact(0x03, n32, 2, r, 32) : callExact(0x03, nullptr, 0, r, 32))) return false;
        size_t n = len < 32 ? len : 32;
        memcpy(out, r, n); out += n; len -= n;
    }
    return true;
}

// ---------------------------------------------------------------- P-256
bool fpga_p256_genkey(uint8_t blobOut[64], uint8_t pubOut64[64]) {
    if (!fpga_has_asym()) return false;
    uint8_t r[128];
    if (!callExact(0x30, nullptr, 0, r, 128)) return false;
    memcpy(blobOut, r, 64); memcpy(pubOut64, r + 64, 64); return true;
}
bool fpga_p256_public(const uint8_t blob[64], uint8_t pubOut64[64]) { return fpga_has_asym() && callExact(0x31, blob, 64, pubOut64, 64); }
bool fpga_p256_sign(const uint8_t blob[64], const uint8_t digest32[32], uint8_t sigOut64[64]) {
    if (!fpga_has_asym()) return false;
    uint8_t p[96]; memcpy(p, blob, 64); memcpy(p + 64, digest32, 32);
    return callExact(0x32, p, 96, sigOut64, 64);
}
bool fpga_p256_ecdh(const uint8_t blob[64], const uint8_t peerPub64[64], uint8_t secretOut32[32]) {
    if (!fpga_has_asym()) return false;
    uint8_t p[128]; memcpy(p, blob, 64); memcpy(p + 64, peerPub64, 64);
    return callExact(0x33, p, 128, secretOut32, 32);
}
bool fpga_p256_verify(const uint8_t digest32[32], const uint8_t sig64[64], const uint8_t pub64[64]) {
    if (!fpga_has_asym()) return false;
    uint8_t p[160]; memcpy(p, digest32, 32); memcpy(p + 32, sig64, 64); memcpy(p + 96, pub64, 64);
    size_t n = 0;
    return call(0x34, p, 160, nullptr, 0, &n, 6000) && n == 0;
}
bool fpga_p256_import(const uint8_t raw32[32], uint8_t blobOut[64]) { return fpga_has_asym() && callExact(0x35, raw32, 32, blobOut, 64); }

// ---------------------------------------------------------------- Ed25519
bool fpga_ed25519_genkey(uint8_t blobOut[64], uint8_t pubOut32[32]) {
    if (!fpga_has_asym()) return false;
    uint8_t r[96];
    if (!callExact(0x40, nullptr, 0, r, 96)) return false;
    memcpy(blobOut, r, 64); memcpy(pubOut32, r + 64, 32); return true;
}
bool fpga_ed25519_public(const uint8_t blob[64], uint8_t pubOut32[32]) { return fpga_has_asym() && callExact(0x41, blob, 64, pubOut32, 32); }
bool fpga_ed25519_sign(const uint8_t blob[64], const uint8_t *msg, size_t len, uint8_t sigOut64[64]) {
    if (!fpga_has_asym() || len + 64 > FPGA_MAX_PAYLOAD) return false;
    uint8_t *p = (uint8_t *)malloc(len + 64);
    if (!p) return false;
    memcpy(p, blob, 64); if (len) memcpy(p + 64, msg, len);
    bool ok = callExact(0x42, p, len + 64, sigOut64, 64, 5000);
    free(p); return ok;
}
bool fpga_ed25519_import(const uint8_t seed32[32], uint8_t blobOut[64]) { return fpga_has_asym() && callExact(0x43, seed32, 32, blobOut, 64); }

// ---------------------------------------------------------------- ML-DSA
static bool mldsa_dims(int ps, size_t &sk, size_t &pk, size_t &sig, uint8_t &idx) {
    switch (ps) {
        case 44: sk = 2560; pk = 1312; sig = 2420; idx = 0; return true;
        case 65: sk = 4032; pk = 1952; sig = 3309; idx = 1; return true;
        case 87: sk = 4896; pk = 2592; sig = 4627; idx = 2; return true;
    }
    return false;
}
size_t fpga_mldsa_blob_len(int ps) { size_t sk, pk, sig; uint8_t i; return mldsa_dims(ps, sk, pk, sig, i) ? sk + 32 : 0; }

bool fpga_mldsa_genkey(int ps, uint8_t *blobOut, uint8_t *pubOut) {
    size_t sk, pk, sig; uint8_t idx;
    if (!fpga_has_pq() || !mldsa_dims(ps, sk, pk, sig, idx)) return false;
    size_t total = sk + 32 + pk;
    uint8_t *r = (uint8_t *)malloc(total);
    if (!r) return false;
    bool ok = callExact(0x60 + idx, nullptr, 0, r, total, 8000);
    if (ok) { memcpy(blobOut, r, sk + 32); memcpy(pubOut, r + sk + 32, pk); }
    memset(r, 0, total); free(r);
    return ok;
}

bool fpga_mldsa_sign(int ps, const uint8_t *blob, const uint8_t *msg, size_t msgLen, uint8_t *sigOut, size_t *sigLen) {
    size_t sk, pk, sig; uint8_t idx;
    if (!fpga_has_pq() || !mldsa_dims(ps, sk, pk, sig, idx)) return false;
    size_t bl = sk + 32, total = bl + 32 + msgLen;
    if (total > FPGA_MAX_PAYLOAD) return false;
    uint8_t *p = (uint8_t *)malloc(total);
    if (!p) return false;
    memcpy(p, blob, bl); memset(p + bl, 0, 32); if (msgLen) memcpy(p + bl + 32, msg, msgLen);   // hedge randomness comes from the FPGA TRNG
    bool ok = callExact(0x68 + idx, p, total, sigOut, sig, 30000);
    memset(p, 0, total); free(p);
    if (ok && sigLen) *sigLen = sig;
    return ok;
}

// ---------------------------------------------------------------- RSA-2048
bool fpga_rsa_genkey(uint8_t blobOut[FPGA_RSA_BLOB_LEN], uint8_t nOut256[256]) {
    if (!fpga_has_rsa()) return false;
    uint8_t *r = (uint8_t *)malloc(FPGA_RSA_BLOB_LEN + 256);
    if (!r) return false;
    bool ok = callExact(0x70, nullptr, 0, r, FPGA_RSA_BLOB_LEN + 256, 600000);
    if (ok) { memcpy(blobOut, r, FPGA_RSA_BLOB_LEN); memcpy(nOut256, r + FPGA_RSA_BLOB_LEN, 256); }
    memset(r, 0, FPGA_RSA_BLOB_LEN + 256); free(r);
    return ok;
}
bool fpga_rsa_public(const uint8_t blob[FPGA_RSA_BLOB_LEN], uint8_t nOut256[256]) {
    return fpga_has_rsa() && callExact(0x71, blob, FPGA_RSA_BLOB_LEN, nOut256, 256, 10000);
}
bool fpga_rsa_sign_sha256(const uint8_t blob[FPGA_RSA_BLOB_LEN], const uint8_t digest32[32], uint8_t sigOut256[256]) {
    if (!fpga_has_rsa()) return false;
    uint8_t p[FPGA_RSA_BLOB_LEN + 32];
    memcpy(p, blob, FPGA_RSA_BLOB_LEN); memcpy(p + FPGA_RSA_BLOB_LEN, digest32, 32);
    bool ok = callExact(0x72, p, sizeof(p), sigOut256, 256, 30000);
    memset(p, 0, sizeof(p));
    return ok;
}

// ---------------------------------------------------------------- hashing
bool fpga_sha512(const uint8_t *data, size_t len, uint8_t out64[64]) { return fpga_has_asym() && callExact(0x50, data, len, out64, 64); }
bool fpga_sha256(const uint8_t *data, size_t len, uint8_t out32[32]) { return fpga_has_sym() && callExact(0x10, data, len, out32, 32); }
bool fpga_hmac_sha256(const uint8_t *key, size_t keyLen, const uint8_t *data, size_t len, uint8_t out32[32]) {
    if (!fpga_has_sym() || keyLen > 64 || len + 1 + keyLen > FPGA_MAX_PAYLOAD) return false;
    uint8_t *p = (uint8_t *)malloc(1 + keyLen + len);
    if (!p) return false;
    p[0] = (uint8_t)keyLen; memcpy(p + 1, key, keyLen); if (len) memcpy(p + 1 + keyLen, data, len);
    bool ok = callExact(0x11, p, 1 + keyLen + len, out32, 32);
    free(p); return ok;
}
bool fpga_pbkdf2_sha256(const uint8_t *pw, size_t pwLen, const uint8_t *salt, size_t saltLen,
                        uint32_t iterations, uint8_t *out, size_t outLen) {
    if (!fpga_has_sym() || pwLen > 64 || outLen == 0 || outLen > 1024 || iterations == 0 || 7 + pwLen + saltLen > FPGA_MAX_PAYLOAD) return false;
    uint8_t *p = (uint8_t *)malloc(7 + pwLen + saltLen);
    if (!p) return false;
    p[0] = iterations; p[1] = iterations >> 8; p[2] = iterations >> 16; p[3] = iterations >> 24;
    p[4] = outLen & 0xFF; p[5] = outLen >> 8; p[6] = (uint8_t)pwLen;
    memcpy(p + 7, pw, pwLen); if (saltLen) memcpy(p + 7 + pwLen, salt, saltLen);
    // ~136 clock cycles per iteration at 27 MHz (5 us), per 32-byte output block
    uint32_t blocks = (uint32_t)((outLen + 31) / 32);
    uint32_t t = 3000 + blocks * (uint32_t)((uint64_t)iterations * 6 / 1000 + 50);
    bool ok = callExact(0x12, p, 7 + pwLen + saltLen, out, outLen, t);
    free(p); return ok;
}

// ---------------------------------------------------------------- AES-256
bool fpga_aes_set_key(const uint8_t key32[32]) { size_t n; return fpga_has_aes() && call(0x20, key32, 32, nullptr, 0, &n); }

static bool aes_op(uint8_t mode, const uint8_t *iv, size_t ivLen, const uint8_t *aad, size_t aadLen,
                   const uint8_t *in, size_t len, const uint8_t *tagIn, uint8_t *out, uint8_t *tagOut) {
    if (!fpga_has_aes()) return false;
    size_t total = 21 + aadLen + len + (tagIn ? 16 : 0);
    if (total > FPGA_MAX_PAYLOAD) return false;
    uint8_t *p = (uint8_t *)malloc(total);
    uint8_t *r = (uint8_t *)malloc(len + 16);
    if (!p || !r) { free(p); free(r); return false; }
    p[0] = mode; memset(p + 1, 0, 16); memcpy(p + 1, iv, ivLen);
    p[17] = aadLen & 0xFF; p[18] = aadLen >> 8; p[19] = len & 0xFF; p[20] = len >> 8;
    size_t o = 21;
    if (aadLen) { memcpy(p + o, aad, aadLen); o += aadLen; }
    if (len) { memcpy(p + o, in, len); o += len; }
    if (tagIn) memcpy(p + o, tagIn, 16);
    size_t want = len + ((mode == 4) ? 16 : 0), n = 0;
    bool ok = call(0x21, p, total, r, len + 16, &n, 5000) && n == want;
    if (ok) { if (len) memcpy(out, r, len); if (tagOut) memcpy(tagOut, r + len, 16); }
    free(p); free(r);
    return ok;
}
bool fpga_aes_cbc(bool encrypt, const uint8_t iv16[16], const uint8_t *in, size_t len, uint8_t *out) {
    return aes_op(encrypt ? 2 : 3, iv16, 16, nullptr, 0, in, len, nullptr, out, nullptr);
}
bool fpga_aes_gcm_encrypt(const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                          const uint8_t *in, size_t len, uint8_t *out, uint8_t tag16[16]) {
    return aes_op(4, iv12, 12, aad, aadLen, in, len, nullptr, out, tag16);
}
bool fpga_aes_gcm_decrypt(const uint8_t iv12[12], const uint8_t *aad, size_t aadLen,
                          const uint8_t *in, size_t len, const uint8_t tag16[16], uint8_t *out) {
    return aes_op(5, iv12, 12, aad, aadLen, in, len, tag16, out, nullptr);
}
