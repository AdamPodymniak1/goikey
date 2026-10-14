// Host-side test of src/FpgaAccel.cpp (UART transport) against the real board:
//   g++ -std=c++17 -I include hw/accel/host/host_test.cpp src/FpgaAccel.cpp -o /tmp/fpga_host_test
//   /tmp/fpga_host_test /dev/ttyUSB1
// The expected values come from known-answer vectors (FIPS / RFC), so no crypto library is needed.
#include "FpgaAccel.h"
#include <stdio.h>
#include <string.h>
static int fails = 0;
static void check(const char *n, bool ok) { printf("[%s] %s\n", ok ? "PASS" : "FAIL", n); fails += !ok; }
static void hexs(const char *h, uint8_t *o, size_t n) { for (size_t i = 0; i < n; i++) { unsigned v; sscanf(h + 2 * i, "%2x", &v); o[i] = v; } }
int main(int argc, char **argv) {
    if (!fpga_init_uart(argc > 1 ? argv[1] : "/dev/ttyUSB1")) { printf("no accelerator found\n"); return 2; }
    printf("caps=%08x hash=%d aes=%d asym=%d mldsa=%d rsa=%d\n", fpga_caps(), fpga_has_sym(), fpga_has_aes(), fpga_has_asym(), fpga_has_pq(), fpga_has_rsa());
    uint8_t uid[16]; check("uid", fpga_uid(uid));
    uint8_t r1[32], r2[32]; check("random", fpga_fill_random(r1, 32) && fpga_fill_random(r2, 32) && memcmp(r1, r2, 32));
    if (fpga_has_sym()) {
        uint8_t h[32], e[32];
        check("sha256(abc)", fpga_sha256((const uint8_t *)"abc", 3, h) && (hexs("ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad", e, 32), !memcmp(h, e, 32)));
        // RFC 4231 case 2
        check("hmac-sha256 (RFC 4231 #2)", fpga_hmac_sha256((const uint8_t *)"Jefe", 4, (const uint8_t *)"what do ya want for nothing?", 28, h)
              && (hexs("5bdcc146bf60754e6a042426089575c75a003f089d2739839dec58b964ec3843", e, 32), !memcmp(h, e, 32)));
        // RFC 6070 style (PBKDF2-HMAC-SHA256, "password"/"salt", 4096 it, 32 B)
        check("pbkdf2-sha256 4096", fpga_pbkdf2_sha256((const uint8_t *)"password", 8, (const uint8_t *)"salt", 4, 4096, h, 32)
              && (hexs("c5e478d59288c841aa530db6845c4c8d962893a001ce4e11a4963873aa98134a", e, 32), !memcmp(h, e, 32)));
    }
    if (fpga_has_aes()) {
        // NIST SP 800-38A F.1.5 (AES-256 ECB first block == CBC with zero IV)
        uint8_t key[32], pt[16], ct[16], iv[16] = {0}, out[16];
        hexs("603deb1015ca71be2b73aef0857d77811f352c073b6108d72d9810a30914dff4", key, 32);
        hexs("6bc1bee22e409f96e93d7e117393172a", pt, 16); hexs("f3eed1bdb5d2a03c064b5a7e3db181f8", ct, 16);
        check("aes-256 key", fpga_aes_set_key(key));
        check("aes-256-cbc encrypt (NIST)", fpga_aes_cbc(true, iv, pt, 16, out) && !memcmp(out, ct, 16));
        check("aes-256-cbc decrypt (NIST)", fpga_aes_cbc(false, iv, ct, 16, out) && !memcmp(out, pt, 16));
        // GCM round trip + tamper
        uint8_t iv12[12] = {1,2,3,4,5,6,7,8,9,10,11,12}, c[32], t[16], d[32], msg[32];
        for (int i = 0; i < 32; i++) msg[i] = i;
        check("aes-gcm encrypt", fpga_aes_gcm_encrypt(iv12, (const uint8_t *)"aad", 3, msg, 32, c, t));
        check("aes-gcm decrypt", fpga_aes_gcm_decrypt(iv12, (const uint8_t *)"aad", 3, c, 32, t, d) && !memcmp(d, msg, 32));
        t[0] ^= 1; check("aes-gcm rejects tampered tag", !fpga_aes_gcm_decrypt(iv12, (const uint8_t *)"aad", 3, c, 32, t, d) && fpga_last_status() == FPGA_AUTH_FAIL);
    }
    if (fpga_has_asym()) {
        uint8_t h[64], e[64];
        check("sha512(abc)", fpga_sha512((const uint8_t *)"abc", 3, h) && (hexs("ddaf35a193617abacc417349ae20413112e6fa4e89a97ea20a9eeee64b55d39a2192992a274fc1a836ba3c23a3feebbd454d4423643ce80e2a9ac94fa54ca49f", e, 64), !memcmp(h, e, 64)));
        uint8_t blob[64], pub[64], sig[64], dig[32] = {1,2,3}, pub2[64];
        check("p256 genkey", fpga_p256_genkey(blob, pub));
        check("p256 public == genkey public", fpga_p256_public(blob, pub2) && !memcmp(pub, pub2, 64));
        check("p256 sign", fpga_p256_sign(blob, dig, sig));
        check("p256 verify (FPGA)", fpga_p256_verify(dig, sig, pub));
        dig[0] ^= 1; check("p256 verify rejects wrong digest", !fpga_p256_verify(dig, sig, pub));
        // RFC 8032 test 1 (Ed25519, empty message)
        uint8_t seed[32], eb[64], epub[32], expub[32], esig[64], exsig[64];
        hexs("9d61b19deffd5a60ba844af492ec2cc44449c5697b326919703bac031cae7f60", seed, 32);
        hexs("d75a980182b10ab7d54bfed3c964073a0ee172f3daa62325af021a68f707511a", expub, 32);
        hexs("e5564300c360ac729086e2cc806e828a84877f1eb8e5d974d873e065224901555fb8821590a33bacc61e39701cf9b46bd25bf5f0595bbe24655141438e7a100b", exsig, 64);
        check("ed25519 import (RFC 8032 #1)", fpga_ed25519_import(seed, eb));
        check("ed25519 public == RFC 8032", fpga_ed25519_public(eb, epub) && !memcmp(epub, expub, 32));
        check("ed25519 signature == RFC 8032", fpga_ed25519_sign(eb, nullptr, 0, esig) && !memcmp(esig, exsig, 64));
    }
    if (fpga_has_pq()) {                                                  // ML-DSA-44 sign/verify is checked by selftest_pq.py (needs the C verifier); here: shapes and tamper detection
        static uint8_t blob[4928], pk[2592], sig[4627]; size_t sl = 0; const uint8_t m[5] = {'h','e','l','l','o'};
        check("ml-dsa-44 keygen", fpga_mldsa_genkey(44, blob, pk));
        check("ml-dsa-44 sign", fpga_mldsa_sign(44, blob, m, 5, sig, &sl) && sl == 2420);
        blob[40] ^= 1; check("ml-dsa-44 rejects a tampered blob", !fpga_mldsa_sign(44, blob, m, 5, sig, &sl) && fpga_last_status() == FPGA_AUTH_FAIL);
    }
    if (fpga_has_rsa()) {
        static uint8_t rb[FPGA_RSA_BLOB_LEN], n[256], n2[256], sg[256]; uint8_t dg[32] = {9, 8, 7};
        check("rsa-2048 keygen (takes a while)", fpga_rsa_genkey(rb, n));
        check("rsa public == keygen modulus", fpga_rsa_public(rb, n2) && !memcmp(n, n2, 256));
        check("rsa sign", fpga_rsa_sign_sha256(rb, dg, sg));
    }
    printf(fails ? "\n%d FAILED\n" : "\nALL PASS\n", fails);
    return fails != 0;
}
