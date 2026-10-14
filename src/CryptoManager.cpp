#include "CryptoManager.h"

#include <Arduino.h>
#include "mbedtls/md.h"
#include "mbedtls/gcm.h"
#include "mbedtls/ecdh.h"
#include "mbedtls/aes.h"
#include "mbedtls/pkcs5.h"
#include "mbedtls/ecdsa.h"
#include "mbedtls/pk.h"
#include "mbedtls/asn1write.h"
#include "mbedtls/error.h"
#include "mbedtls/version.h"
#include "StorageManager.h"
#include "AteccManager.h"
#include "CryptoAccel.h"
#include "FpgaAccel.h"
#include <Ed25519.h>
#include <nvs_flash.h>
#include <nvs.h>

#define PBKDF2_ITERATIONS 10000
#define HASH_SIZE 32
#define SALT_SIZE 16

#define FI_MAGIC_START  0x1A2B3C4D
#define FI_MAGIC_PASSED 0x5E6F7A8B
#define FI_MAGIC_FAILED 0xDEADBEEF

bool encryptionActive = false;
byte aesKey[32] = {0};

SecureTerminal Terminal;

// Fills `len` bytes from the ESP32's own TRNG, then - if an ATECC chip is
// present - mixes in an equal amount of its hardware RNG output via XOR.
// XOR-combining two independent entropy sources is a standard defense in
// depth: the result is at least as unpredictable as the stronger source,
// so a missing/failed/tampered ATECC can only ever fall back to the
// ESP32's own TRNG, never make output weaker than what we had before.
static void secureFillRandom(uint8_t *out, size_t len) {
  esp_fill_random(out, len);

  // The FPGA TRNG (when attached) is XOR-mixed in exactly like the ATECC below: an absent or failing
  // accelerator can never make the output weaker than the ESP32's own TRNG.
  accel_mix_random(out, len);

  if (!atecc_available()) return;

  uint8_t *ateccBytes = (uint8_t *)malloc(len);
  if (!ateccBytes) return;

  if (atecc_fill_random(ateccBytes, len)) {
    for (size_t i = 0; i < len; i++) out[i] ^= ateccBytes[i];
  }
  free(ateccBytes);
}

static int hw_rng_callback(void *p_rng, unsigned char *output, size_t output_len) {
  (void)p_rng;
  secureFillRandom(output, output_len);
  return 0;
}

size_t fromHex(const String &hex, byte *output, size_t max_len) {
  size_t len = hex.length() / 2;
  if (len > max_len) len = max_len;

  memset(output, 0, max_len); 

  for (size_t i = 0; i < len; i++) {
    String byteString = hex.substring(i * 2, i * 2 + 2);
    output[i] = (byte)strtol(byteString.c_str(), NULL, 16);
  }

  return len; 
}

String toHex(const byte *data, size_t len) {
  String out;
  out.reserve(len * 2);

  for (size_t i = 0; i < len; i++) {
    char buf[3];
    sprintf(buf, "%02x", data[i]);
    out += buf;
  }
  return out;
}

void initCrypto() {
  Serial.println("[SYS] CRYPTO_INIT");
  atecc_init(); // optional hardware entropy/keygen source; absence is non-fatal
  accel_init(); // optional FPGA accelerator (SPI); without it everything runs on the ESP32
  init_aes_nonce_subsystem();
  secureFillRandom(aesKey, sizeof(aesKey));
  encryptionActive = false;
}

String encryptMsg(const String &plainText) {
  if (!encryptionActive) return plainText;

  byte iv[12];
  generate_aes_gcm_nonce(iv);

  size_t len = plainText.length();
  byte *cipher = (byte *)malloc(len);
  byte tag[16];

  if (!cipher) return "";

  if (!accel_aes256_gcm_encrypt(aesKey, iv, NULL, 0, (const byte *)plainText.c_str(), len, cipher, tag)) { free(cipher); return ""; }

  String result = "ENC:" + toHex(iv, 12) + ":" + toHex(cipher, len) + toHex(tag, 16);
  free(cipher);
  return result;
}

String decryptMsg(const String &payload) {
  int c1 = payload.indexOf(':');
  int c2 = payload.indexOf(':', c1 + 1);
  if (c1 == -1 || c2 == -1) return "";

  String ivHex = payload.substring(c1 + 1, c2);
  String dataHex = payload.substring(c2 + 1);

  if (ivHex.length() != 24) return ""; 

  size_t dataLen = dataHex.length() / 2;
  if (dataLen < 16) return "";

  byte iv[12];
  fromHex(ivHex, iv, sizeof(iv));

  byte *full = (byte *)malloc(dataLen);
  if (!full) return "";

  fromHex(dataHex, full, dataLen);

  size_t cipherLen = dataLen - 16;
  byte *tag = full + cipherLen;
  byte *plain = (byte *)malloc(cipherLen + 1);

  if (!plain) {
    free(full);
    return "";
  }

  bool gcmOk = accel_aes256_gcm_decrypt(aesKey, iv, NULL, 0, full, cipherLen, tag, plain);
  free(full);

  if (!gcmOk) {
    free(plain);
    return "";
  }

  plain[cipherLen] = '\0';
  String out = String((char *)plain);
  free(plain);

  return out;
}

void processHandshake(const String &clientPubHex) {
  volatile uint32_t fi_state = FI_MAGIC_START;

  if (clientPubHex.length() != 130) {
    Serial.println("[ERR] ECDH_INVALID_KEY_LENGTH");
    return;
  }

  delay(esp_random() % 15 + 2); 

  mbedtls_ecdh_context ctx;
  mbedtls_ecdh_init(&ctx);

  int ret = mbedtls_ecp_group_load(&ctx.grp, MBEDTLS_ECP_DP_SECP256R1);
  if (ret != 0) {
    Serial.println("[ERR] ECDH_GRP_LOAD_FAIL");
    mbedtls_ecdh_free(&ctx);
    return;
  }

  ret = mbedtls_ecdh_gen_public(&ctx.grp, &ctx.d, &ctx.Q, hw_rng_callback, NULL);
  if (ret != 0) {
    Serial.println("[ERR] ECDH_GEN_PUB_FAIL");
    mbedtls_ecdh_free(&ctx);
    return;
  }

  yield(); 

  byte clientPubBuf[65] = {0}; 
  fromHex(clientPubHex, clientPubBuf, sizeof(clientPubBuf));

  ret = mbedtls_ecp_point_read_binary(&ctx.grp, &ctx.Qp, clientPubBuf, sizeof(clientPubBuf));

  if (ret != 0) {
    Serial.println("[ERR] ECDH_PEER_KEY_INVALID");
    mbedtls_ecdh_free(&ctx);
    return;
  }

  delay(esp_random() % 10 + 1); 

  ret = mbedtls_ecdh_compute_shared(&ctx.grp, &ctx.z, &ctx.Qp, &ctx.d, hw_rng_callback, NULL);
  if (ret != 0) {
    Serial.println("[ERR] ECDH_COMPUTE_SHARED_FAIL");
    mbedtls_ecdh_free(&ctx);
    return;
  }

  yield(); 

  byte sharedSecret[32];
  mbedtls_mpi_write_binary(&ctx.z, sharedSecret, sizeof(sharedSecret));
  mbedtls_md(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), sharedSecret, sizeof(sharedSecret), aesKey);

  uint8_t exportBuf[70];
  size_t exportLen = 0;
  mbedtls_ecp_point_write_binary(&ctx.grp, &ctx.Q, MBEDTLS_ECP_PF_UNCOMPRESSED, &exportLen, exportBuf, sizeof(exportBuf));

  if (fi_state != FI_MAGIC_START) {
    ESP.restart(); 
  }

  fi_state = FI_MAGIC_PASSED;
  encryptionActive = true;

  Serial.print("DH_ACK:");
  Serial.println(toHex(exportBuf, exportLen));

  mbedtls_ecdh_free(&ctx);
}

bool fidoEcdhSharedSecret(const uint8_t devicePriv32[32], const uint8_t peerXY64[64], uint8_t sharedOut32[32]) {
  mbedtls_ecdh_context ctx;
  mbedtls_ecdh_init(&ctx);

  int ret = mbedtls_ecp_group_load(&ctx.grp, MBEDTLS_ECP_DP_SECP256R1);
  if (ret != 0) { mbedtls_ecdh_free(&ctx); return false; }

  ret = mbedtls_mpi_read_binary(&ctx.d, devicePriv32, 32);
  if (ret != 0) { mbedtls_ecdh_free(&ctx); return false; }

  uint8_t peerUncompressed[65];
  peerUncompressed[0] = 0x04;
  memcpy(peerUncompressed + 1, peerXY64, 64);

  ret = mbedtls_ecp_point_read_binary(&ctx.grp, &ctx.Qp, peerUncompressed, sizeof(peerUncompressed));
  if (ret != 0) { mbedtls_ecdh_free(&ctx); return false; }

  ret = mbedtls_ecdh_compute_shared(&ctx.grp, &ctx.z, &ctx.Qp, &ctx.d, hw_rng_callback, NULL);
  if (ret != 0) { mbedtls_ecdh_free(&ctx); return false; }

  uint8_t rawShared[32];
  mbedtls_mpi_write_binary(&ctx.z, rawShared, sizeof(rawShared));
  mbedtls_md(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), rawShared, sizeof(rawShared), sharedOut32);
  memset(rawShared, 0, sizeof(rawShared));

  mbedtls_ecdh_free(&ctx);
  return true;
}

bool aesCbcZeroIvEncrypt(const uint8_t key32[32], const uint8_t *in, size_t len, uint8_t *out) {
  if (len % 16 != 0) return false;
  uint8_t iv[16] = {0};
  return accel_aes256_cbc(true, key32, iv, in, len, out);
}

bool aesCbcZeroIvDecrypt(const uint8_t key32[32], const uint8_t *in, size_t len, uint8_t *out) {
  if (len % 16 != 0) return false;
  uint8_t iv[16] = {0};
  return accel_aes256_cbc(false, key32, iv, in, len, out);
}

void hmacSha256Raw(const uint8_t key32[32], const uint8_t *data, size_t len, uint8_t out32[32]) {
  accel_hmac_sha256(key32, 32, data, len, out32);
}

size_t SecureTerminal::write(uint8_t c) {
  buffer += (char)c;
  if (buffer.length() > 512) flush();
  return 1;
}

size_t SecureTerminal::write(const uint8_t *buf, size_t size) {
  for (size_t i = 0; i < size; i++) {
    buffer += (char)buf[i];
    if (buffer.length() > 512) flush();
  }
  return size;
}

void SecureTerminal::flush() {
  if (buffer.length() == 0) return;

  String out = buffer;
  buffer = "";

  if (encryptionActive)
    Serial.println(encryptMsg(out));
  else
    Serial.print(out);
}

String generateRandomPassword(size_t length) {
    if (length < 4) length = 4;

    const char lowerPool[] = "abcdefghijkmnopqrstuvwxyz";
    const char upperPool[] = "ABCDEFGHIJKLMNPQRSTUVWXYZ";
    const char numPool[] = "23456789";
    const char symPool[] = "!@#$%^*()-_=+";
    const char allPool[] = "abcdefghijkmnopqrstuvwxyzABCDEFGHIJKLMNPQRSTUVWXYZ23456789!@#$%^*()-_=+";

    uint8_t *randomBytes = (uint8_t *)malloc(length);
    if (!randomBytes) return "";

    secureFillRandom(randomBytes, length);

    String password = "";
    password.reserve(length);

    password += lowerPool[randomBytes[0] % (sizeof(lowerPool) - 1)];
    password += upperPool[randomBytes[1] % (sizeof(upperPool) - 1)];
    password += numPool[randomBytes[2] % (sizeof(numPool) - 1)];
    password += symPool[randomBytes[3] % (sizeof(symPool) - 1)];

    for (size_t i = 4; i < length; i++) {
        password += allPool[randomBytes[i] % (sizeof(allPool) - 1)];
    }

    for (size_t i = 0; i < length; i++) {
        size_t j = randomBytes[i] % length;
        char temp = password[i];
        password[i] = password[j];
        password[j] = temp;
    }

    free(randomBytes);
    return password;
}

String encryptStoragePayload(const String &plainText, const byte *key256) {
  byte iv[12];
  generate_aes_gcm_nonce(iv);

  size_t len = plainText.length();
  byte *cipher = (byte *)malloc(len);
  byte tag[16];

  if (!cipher) return "";

  if (!accel_aes256_gcm_encrypt(key256, iv, NULL, 0, (const byte *)plainText.c_str(), len, cipher, tag)) { free(cipher); return ""; }

  String result = toHex(iv, 12) + ":" + toHex(cipher, len) + ":" + toHex(tag, 16);
  free(cipher);
  return result;
}

String decryptStoragePayload(const String &payload, const byte *key256) {
  int c1 = payload.indexOf(':');
  int c2 = payload.indexOf(':', c1 + 1);
  if (c1 == -1 || c2 == -1) return "";

  String ivHex = payload.substring(0, c1);
  String cipherHex = payload.substring(c1 + 1, c2);
  String tagHex = payload.substring(c2 + 1);

  if (ivHex.length() != 24 || tagHex.length() != 32) return "";

  size_t cipherLen = cipherHex.length() / 2;
  if (cipherLen == 0) return "";

  byte iv[12];
  byte tag[16];
  fromHex(ivHex, iv, sizeof(iv));
  fromHex(tagHex, tag, sizeof(tag));

  byte *cipher = (byte *)malloc(cipherLen);
  byte *plain = (byte *)malloc(cipherLen + 1);

  if (!cipher || !plain) {
    if (cipher) free(cipher);
    if (plain) free(plain);
    return "";
  }

  fromHex(cipherHex, cipher, cipherLen);

  bool gcmOk = accel_aes256_gcm_decrypt(key256, iv, NULL, 0, cipher, cipherLen, tag, plain);
  free(cipher);

  if (!gcmOk) {
    free(plain);
    return "";
  }

  plain[cipherLen] = '\0';
  String out = String((char *)plain);
  free(plain);
  return out;
}

String hashSHA256(const String &input) {
  uint8_t outputHash[32];

  accel_sha256((const uint8_t*)input.c_str(), input.length(), outputHash);

  return toHex(outputHash, 32);
}

#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    #define M_GRP MBEDTLS_PRIVATE(grp)
    #define M_D   MBEDTLS_PRIVATE(d)
    #define M_Q   MBEDTLS_PRIVATE(Q)
#else
    #define M_GRP grp
    #define M_D   d
    #define M_Q   Q
#endif

bool generateKeypairP256(uint8_t *privateKeyOut, uint8_t *publicKeyOut65) {
    if (privateKeyOut == nullptr || publicKeyOut65 == nullptr) {
        return false;
    }

    mbedtls_ecdsa_context ctx;
    mbedtls_ecdsa_init(&ctx);

    int ret = mbedtls_ecdsa_genkey(&ctx, MBEDTLS_ECP_DP_SECP256R1, hw_rng_callback, NULL);
    if (ret != 0) {
        mbedtls_ecdsa_free(&ctx);
        return false;
    }

    ret = mbedtls_mpi_write_binary(&ctx.M_D, privateKeyOut, 32);
    if (ret != 0) {
        mbedtls_ecdsa_free(&ctx);
        return false;
    }

    size_t writtenLen = 0;
    ret = mbedtls_ecp_point_write_binary(&ctx.M_GRP, &ctx.M_Q, 
                                         MBEDTLS_ECP_PF_UNCOMPRESSED, 
                                         &writtenLen, publicKeyOut65, 65);

    mbedtls_ecdsa_free(&ctx);
    bool ok = (ret == 0 && writtenLen == 65);
    return ok;
}

#if MBEDTLS_VERSION_NUMBER >= 0x03000000
    #define M_GRP MBEDTLS_PRIVATE(grp)
    #define M_D   MBEDTLS_PRIVATE(d)
#else
    #define M_GRP grp
    #define M_D   d
#endif

// Shared by both the software (signECDSA_P256) and ATECC-backed
// (signECDSA_P256_ATECC) signers: packs raw (r, s) values into the DER
// SEQUENCE{INTEGER r, INTEGER s} encoding WebAuthn/FIDO2 signatures use.
static bool derEncodeSignature(mbedtls_mpi &r, mbedtls_mpi &s, uint8_t *sigDerOut, size_t *sigDerLenOut) {
    size_t maxSigCapacity = *sigDerLenOut;
    unsigned char buf[128];
    unsigned char *p = buf + sizeof(buf);
    int len = 0;

    int ret = mbedtls_asn1_write_mpi(&p, buf, &s);
    if (ret < 0) return false;
    len += ret;

    ret = mbedtls_asn1_write_mpi(&p, buf, &r);
    if (ret < 0) return false;
    len += ret;

    ret = mbedtls_asn1_write_len(&p, buf, len);
    if (ret < 0) return false;
    len += ret;

    ret = mbedtls_asn1_write_tag(&p, buf, MBEDTLS_ASN1_CONSTRUCTED | MBEDTLS_ASN1_SEQUENCE);
    if (ret <= 0) return false;
    len += ret;

    if ((size_t)len > maxSigCapacity) {
        Serial.println("[ERR] Provided sigDerOut too small");
        return false;
    }

    memcpy(sigDerOut, p, len);
    *sigDerLenOut = len;
    return true;
}

bool signECDSA_P256(const uint8_t *privateKey32, const uint8_t *digest32, size_t digestLen,
                    uint8_t *sigDerOut, size_t *sigDerLenOut) {
    if (!privateKey32 || !digest32 || digestLen != 32 || !sigDerOut || !sigDerLenOut) {
        return false;
    }

    mbedtls_ecdsa_context ctx;
    mbedtls_ecdsa_init(&ctx);

    if (mbedtls_ecp_group_load(&ctx.M_GRP, MBEDTLS_ECP_DP_SECP256R1) != 0 ||
        mbedtls_mpi_read_binary(&ctx.M_D, privateKey32, 32) != 0) {
        mbedtls_ecdsa_free(&ctx);
        return false;
    }

    mbedtls_mpi r, s;
    mbedtls_mpi_init(&r);
    mbedtls_mpi_init(&s);

    bool ok = false;
    if (mbedtls_ecdsa_sign(&ctx.M_GRP, &r, &s, &ctx.M_D, digest32, digestLen, hw_rng_callback, NULL) != 0) {
        Serial.println("[ERR] Core ECDSA math failed");
    } else {
        ok = derEncodeSignature(r, s, sigDerOut, sigDerLenOut);
    }

    mbedtls_mpi_free(&r);
    mbedtls_mpi_free(&s);
    mbedtls_ecdsa_free(&ctx);
    return ok;
}

// Hardware-backed counterparts of generateKeypairP256/signECDSA_P256: the
// private key is generated by and never leaves the ATECC chip (slot
// `slot` is the key handle instead of a 32-byte private key). Output
// shapes match their software equivalents exactly (65-byte uncompressed
// public key, DER signature) so callers can treat them as drop-in
// alternatives. Both simply return false if no ATECC chip is present.
//
// Not currently wired into FIDO2Manager's credential flow - this repo
// intentionally leaves the chip's zones unlocked (see AteccManager.h), and
// signing behavior on an unlocked chip should be verified against real
// hardware before it backs live credentials.
bool generateKeypairP256_ATECC(uint8_t slot, uint8_t *publicKeyOut65) {
    if (!publicKeyOut65) return false;

    uint8_t pub64[64];
    if (!atecc_genkey_p256(slot, pub64)) return false;

    publicKeyOut65[0] = 0x04;
    memcpy(publicKeyOut65 + 1, pub64, 64);
    return true;
}

bool signECDSA_P256_ATECC(uint8_t slot, const uint8_t *digest32, size_t digestLen,
                           uint8_t *sigDerOut, size_t *sigDerLenOut) {
    if (!digest32 || digestLen != 32 || !sigDerOut || !sigDerLenOut) return false;

    uint8_t rawSig[64];
    if (!atecc_sign_p256(slot, digest32, rawSig)) return false;

    mbedtls_mpi r, s;
    mbedtls_mpi_init(&r);
    mbedtls_mpi_init(&s);

    bool ok = mbedtls_mpi_read_binary(&r, rawSig, 32) == 0 &&
              mbedtls_mpi_read_binary(&s, rawSig + 32, 32) == 0 &&
              derEncodeSignature(r, s, sigDerOut, sigDerLenOut);

    mbedtls_mpi_free(&r);
    mbedtls_mpi_free(&s);
    return ok;
}

bool generateFido2Signature(const String& privateKeyHex, const uint8_t* clientDataHash, size_t hashLen, uint8_t* sigOutBuffer, size_t* sigOutLen) {
    if (privateKeyHex.length() == 0 || hashLen != 32) {
        return false;
    }

    // A 128-hex-character key is an FPGA-wrapped blob (the private key never leaves the accelerator).
    if (privateKeyHex.length() == 2 * FPGA_BLOB_LEN) {
        uint8_t blob[FPGA_BLOB_LEN], raw[64];
        fromHex(privateKeyHex, blob, sizeof(blob));
        bool ok = false;
        if (accel_has_asym_keys() && fpga_p256_sign(blob, clientDataHash, raw)) {
            mbedtls_mpi r, s; mbedtls_mpi_init(&r); mbedtls_mpi_init(&s);
            ok = mbedtls_mpi_read_binary(&r, raw, 32) == 0 && mbedtls_mpi_read_binary(&s, raw + 32, 32) == 0 &&
                 derEncodeSignature(r, s, sigOutBuffer, sigOutLen);
            mbedtls_mpi_free(&r); mbedtls_mpi_free(&s);
        } else {
            Serial.println("[ERR] FPGA-wrapped P-256 key but the accelerator is absent or failed");
        }
        memset(blob, 0, sizeof(blob));
        return ok;
    }
    if (privateKeyHex.length() != 64) return false;

    size_t pkLen = privateKeyHex.length() / 2;
    uint8_t pkBin[32]; 
    fromHex(privateKeyHex, pkBin, pkLen);

    bool success = signECDSA_P256(pkBin, clientDataHash, hashLen, sigOutBuffer, sigOutLen);

    memset(pkBin, 0, sizeof(pkBin));

    return success;
}

static int mbedtls_fido2_rng(void *p_rng, unsigned char *output, size_t output_len) {
    (void)p_rng;
    secureFillRandom(output, output_len);
    return 0;
}

// New FIDO credential key (P-256): generated inside the FPGA and stored as a wrapped blob when the asymmetric
// accelerator is attached, otherwise a normal software key (64 hex characters). Existing software keys keep working.
bool generateCredentialKeyP256(String& privateKeyHexOut, uint8_t* publicKeyOut65) {
    if (accel_has_asym_keys()) {
        uint8_t blob[FPGA_BLOB_LEN], pub64[64];
        if (fpga_p256_genkey(blob, pub64)) {
            publicKeyOut65[0] = 0x04; memcpy(publicKeyOut65 + 1, pub64, 64);
            privateKeyHexOut = toHex(blob, sizeof(blob));
            memset(blob, 0, sizeof(blob));
            return true;
        }
        Serial.println("[ACCEL] FPGA P-256 keygen failed - falling back to a software key");
    }
    uint8_t priv[32];
    if (!generateKeypairP256(priv, publicKeyOut65)) return false;
    privateKeyHexOut = toHex(priv, 32);
    memset(priv, 0, sizeof(priv));
    return true;
}

bool generateEd25519KeyPair(String& privateKeyHexOut, uint8_t* pubKeyXOut) {
    if (accel_has_asym_keys()) {
        uint8_t blob[FPGA_BLOB_LEN], pubf[32];
        if (fpga_ed25519_genkey(blob, pubf)) {
            privateKeyHexOut = toHex(blob, sizeof(blob));
            memcpy(pubKeyXOut, pubf, 32);
            memset(blob, 0, sizeof(blob));
            return true;
        }
        Serial.println("[ACCEL] FPGA Ed25519 keygen failed - falling back to a software key");
    }
    uint8_t priv[32];
    uint8_t pub[32];

    secureFillRandom(priv, 32);

    Ed25519::derivePublicKey(pub, priv);

    privateKeyHexOut = toHex(priv, 32);
    memcpy(pubKeyXOut, pub, 32);

    return true;
}

bool generateRsa2048KeyPair(String& privateKeyHexOut, uint8_t* nOut, size_t* nLen, uint8_t* eOut, size_t* eLen) {
    if (accel_has_rsa_keys()) {                                          // FPGA: wrapped CRT key (672 bytes = 1344 hex characters)
        uint8_t blob[FPGA_RSA_BLOB_LEN];
        if (fpga_rsa_genkey(blob, nOut)) {
            privateKeyHexOut = toHex(blob, sizeof(blob));
            memset(blob, 0, sizeof(blob));
            *nLen = 256; eOut[0] = 0x01; eOut[1] = 0x00; eOut[2] = 0x01; *eLen = 3;
            return true;
        }
        Serial.println("[ACCEL] FPGA RSA keygen failed - falling back to software");
    }
    mbedtls_pk_context ctx;
    mbedtls_pk_init(&ctx);

    if (mbedtls_pk_setup(&ctx, mbedtls_pk_info_from_type(MBEDTLS_PK_RSA)) != 0) {
        mbedtls_pk_free(&ctx);
        return false;
    }

    if (mbedtls_rsa_gen_key(mbedtls_pk_rsa(ctx), mbedtls_fido2_rng, NULL, 2048, 65537) != 0) {
        mbedtls_pk_free(&ctx);
        return false;
    }

    mbedtls_rsa_context *rsa = mbedtls_pk_rsa(ctx);

    unsigned char privDer[1500];
    int len = mbedtls_pk_write_key_der(&ctx, privDer, sizeof(privDer));
    if (len < 0) {
        mbedtls_pk_free(&ctx);
        return false;
    }

    unsigned char* p = privDer + sizeof(privDer) - len;
    privateKeyHexOut = "";
    for(int i = 0; i < len; i++) {
        if(p[i] < 0x10) privateKeyHexOut += "0";
        privateKeyHexOut += String(p[i], HEX);
    }

    mbedtls_mpi_write_binary(&rsa->N, nOut, 256);
    *nLen = 256;
    mbedtls_mpi_write_binary(&rsa->E, eOut, 3);
    *eLen = 3;

    mbedtls_pk_free(&ctx);
    return true;
}

bool generateAlgSignature(int algId, const String& privateKeyHex, const uint8_t* msg, size_t msgLen, uint8_t** sigOut, size_t* sigLen) {
    if (algId == -7) { 
        uint8_t hash[32];
        mbedtls_md(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), msg, msgLen, hash);
        
        *sigOut = (uint8_t*)malloc(300);
        if (!*sigOut) return false;
        *sigLen = 300;
        bool res = generateFido2Signature(privateKeyHex, hash, 32, *sigOut, sigLen);
        if (!res) { free(*sigOut); *sigOut = nullptr; }
        return res;
    } 
    else if (algId == -8) { 
        *sigOut = (uint8_t*)malloc(64);
        if (!*sigOut) return false;
        if (privateKeyHex.length() == 2 * FPGA_BLOB_LEN) {                 // FPGA-wrapped Ed25519 key
            uint8_t blob[FPGA_BLOB_LEN];
            fromHex(privateKeyHex, blob, sizeof(blob));
            bool ok = accel_has_asym_keys() && fpga_ed25519_sign(blob, msg, msgLen, *sigOut);
            memset(blob, 0, sizeof(blob));
            if (!ok) { free(*sigOut); *sigOut = nullptr; Serial.println("[ERR] FPGA-wrapped Ed25519 key but the accelerator is absent or failed"); return false; }
            *sigLen = 64;
            return true;
        }
        uint8_t privBin[32]; uint8_t pubBin[32];
        fromHex(privateKeyHex, privBin, 32);
        Ed25519::derivePublicKey(pubBin, privBin);
        Ed25519::sign(*sigOut, privBin, pubBin, msg, msgLen);
        *sigLen = 64; 
        memset(privBin, 0, sizeof(privBin));
        return true;
    }
    else if (algId == -257) { 
        uint8_t hash[32];
        mbedtls_md(mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), msg, msgLen, hash);

        if (privateKeyHex.length() == 2 * FPGA_RSA_BLOB_LEN) {                // FPGA-wrapped RSA key
            uint8_t blob[FPGA_RSA_BLOB_LEN];
            fromHex(privateKeyHex, blob, sizeof(blob));
            *sigOut = (uint8_t*)malloc(256);
            bool ok = *sigOut && accel_has_rsa_keys() && fpga_rsa_sign_sha256(blob, hash, *sigOut);
            memset(blob, 0, sizeof(blob));
            if (!ok) { free(*sigOut); *sigOut = nullptr; Serial.println("[ERR] FPGA-wrapped RSA key but the accelerator is absent or failed"); return false; }
            *sigLen = 256;
            return true;
        }
        size_t derLen = privateKeyHex.length() / 2;
        uint8_t* derBuf = (uint8_t*)malloc(derLen);
        fromHex(privateKeyHex, derBuf, derLen);
        
        mbedtls_pk_context ctx;
        mbedtls_pk_init(&ctx);
        int ret = mbedtls_pk_parse_key(&ctx, derBuf, derLen, NULL, 0);
        free(derBuf);
        if (ret != 0) { mbedtls_pk_free(&ctx); return false; }
        
        *sigOut = (uint8_t*)malloc(512);
        if (!*sigOut) { mbedtls_pk_free(&ctx); return false; }
        
        size_t slen = 0;
        ret = mbedtls_pk_sign(&ctx, MBEDTLS_MD_SHA256, hash, 32, *sigOut, &slen, mbedtls_fido2_rng, NULL);
        *sigLen = slen;
        mbedtls_pk_free(&ctx);
        if (ret != 0) { free(*sigOut); *sigOut = nullptr; }
        return (ret == 0);
    }
    else if (algId == -48 || algId == -49 || algId == -50) {
        size_t keyLen = privateKeyHex.length() / 2;
        uint8_t* privBin = (uint8_t*)malloc(keyLen);
        if (!privBin) return false;
        fromHex(privateKeyHex, privBin, keyLen);

        int ps = (algId == -48) ? 44 : (algId == -49) ? 65 : 87;
        if (algId == -48) *sigLen = 2420;
        else if (algId == -49) *sigLen = 3309;
        else if (algId == -50) *sigLen = 4627;

        *sigOut = (uint8_t*)malloc(*sigLen);
        if (!*sigOut) { free(privBin); return false; }

        bool success;
        if (keyLen == fpga_mldsa_blob_len(ps)) {                          // FPGA-wrapped key (secret key + 32 bytes)
            success = accel_present() && fpga_has_pq() && fpga_mldsa_sign(ps, privBin, msg, msgLen, *sigOut, sigLen);
            if (!success) Serial.println("[ERR] FPGA-wrapped ML-DSA key but the accelerator is absent or failed");
        } else {
            success = mldsa_sign(algId, *sigOut, sigLen, msg, msgLen, privBin);
        }
        memset(privBin, 0, keyLen);
        free(privBin);
        if (!success) { free(*sigOut); *sigOut = nullptr; }
        return success;
    }
    return false;
}

int decodeBase32(const char* b32, uint8_t* out) {
    int len = strlen(b32);
    int buffer = 0;
    int bitsLeft = 0;
    int count = 0;

    for (int i = 0; i < len; i++) {
        uint8_t val = 0;
        char c = b32[i];

        if (c >= 'A' && c <= 'Z') val = c - 'A';
        else if (c >= 'a' && c <= 'z') val = c - 'a';
        else if (c >= '2' && c <= '7') val = c - '2' + 26;
        else continue;

        buffer = (buffer << 5) | val;
        bitsLeft += 5;

        if (bitsLeft >= 8) {
            out[count++] = (buffer >> (bitsLeft - 8)) & 0xFF;
            bitsLeft -= 8;
        }
    }
    return count;
}

String generateTOTP(const String& base32Secret, uint32_t unixTime) {
    uint8_t key[64];
    int keyLen = decodeBase32(base32Secret.c_str(), key);

    uint64_t timeStep = unixTime / 30;
    uint8_t timeBytes[8];

    for (int i = 7; i >= 0; i--) {
        timeBytes[i] = timeStep & 0xFF;
        timeStep >>= 8;
    }

    uint8_t hash[20];
    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA1), 1);
    mbedtls_md_hmac_starts(&ctx, key, keyLen);
    mbedtls_md_hmac_update(&ctx, timeBytes, 8);
    mbedtls_md_hmac_finish(&ctx, hash);
    mbedtls_md_free(&ctx);

    int offset = hash[19] & 0x0F;
    uint32_t binary = ((hash[offset] & 0x7F) << 24) |
                      ((hash[offset + 1] & 0xFF) << 16) |
                      ((hash[offset + 2] & 0xFF) << 8) |
                      (hash[offset + 3] & 0xFF);

    uint32_t otp = binary % 1000000;
    char code[7];
    sprintf(code, "%06u", otp);

    return String(code);
}

void getFidoHardwareKey(byte* outKey256) {
    uint8_t mac[6];

    if (esp_efuse_mac_get_default(mac) != ESP_OK) {
        memset(mac, 0xAA, 6);
    }

    mbedtls_md_context_t ctx;
    mbedtls_md_init(&ctx);
    mbedtls_md_setup(&ctx, mbedtls_md_info_from_type(MBEDTLS_MD_SHA256), 0);
    mbedtls_md_starts(&ctx);
    mbedtls_md_update(&ctx, mac, 6);
    mbedtls_md_update(&ctx, (const unsigned char*)"VAULT_APP_FIDO2_ISOLATION_SECRET", 32);
    mbedtls_md_finish(&ctx, outKey256);
    mbedtls_md_free(&ctx);
}

extern "C" {
    #include "api_mldsa44.h"
    #include "api_mldsa65.h"
    #include "api_mldsa87.h"
}

// Like generateMlDsaKeyPair, but uses the FPGA (private key = wrapped blob, 32 bytes longer than the raw key) when the
// pq bitstream is attached and falls back to a software key otherwise. *privLen reports the stored length.
bool generateMlDsaKeyPairEx(int algId, uint8_t* privKeyOut, size_t privCap, size_t* privLen, uint8_t* pubKeyOut) {
    int ps = (algId == -48) ? 44 : (algId == -49) ? 65 : (algId == -50) ? 87 : 0;
    if (!ps) return false;
    size_t blobLen = fpga_mldsa_blob_len(ps);
    if (accel_present() && fpga_has_pq() && blobLen <= privCap) {
        if (fpga_mldsa_genkey(ps, privKeyOut, pubKeyOut)) { *privLen = blobLen; return true; }
        Serial.println("[ACCEL] FPGA ML-DSA keygen failed - falling back to a software key");
    }
    size_t rawLen = blobLen - 32;
    if (rawLen > privCap) return false;
    if (!generateMlDsaKeyPair(algId, privKeyOut, pubKeyOut)) return false;
    *privLen = rawLen;
    return true;
}

bool generateMlDsaKeyPair(int algId, uint8_t* privKeyOut, uint8_t* pubKeyOut) {
    if (algId == -48) return PQCLEAN_MLDSA44_CLEAN_crypto_sign_keypair(pubKeyOut, privKeyOut) == 0;
    if (algId == -49) return PQCLEAN_MLDSA65_CLEAN_crypto_sign_keypair(pubKeyOut, privKeyOut) == 0;
    if (algId == -50) return PQCLEAN_MLDSA87_CLEAN_crypto_sign_keypair(pubKeyOut, privKeyOut) == 0;
    return false;
}

bool mldsa_sign(int algId, uint8_t* sigOut, size_t* sigLen, const uint8_t* hash, size_t hashLen, const uint8_t* privKey) {
    if (algId == -48) return PQCLEAN_MLDSA44_CLEAN_crypto_sign_signature(sigOut, sigLen, hash, hashLen, privKey) == 0;
    if (algId == -49) return PQCLEAN_MLDSA65_CLEAN_crypto_sign_signature(sigOut, sigLen, hash, hashLen, privKey) == 0;
    if (algId == -50) return PQCLEAN_MLDSA87_CLEAN_crypto_sign_signature(sigOut, sigLen, hash, hashLen, privKey) == 0;
    return false;
}

static uint32_t boot_counter = 0;
static uint32_t session_counter = 0;
static bool nonce_subsystem_initialized = false;

void init_aes_nonce_subsystem() {
    nvs_handle_t my_handle;
    esp_err_t err = nvs_open("storage", NVS_READWRITE, &my_handle);
    if (err == ESP_OK) {
        err = nvs_get_u32(my_handle, "boot_cnt", &boot_counter);
        if (err == ESP_ERR_NVS_NOT_FOUND) boot_counter = 0;
        
        boot_counter++;
        nvs_set_u32(my_handle, "boot_cnt", boot_counter);
        nvs_commit(my_handle);
        nvs_close(my_handle);
        
        nonce_subsystem_initialized = true;
    }
}

void generate_aes_gcm_nonce(byte *nonce_out) {
    if (!nonce_subsystem_initialized) abort();
    
    nonce_out[0] = (boot_counter >> 24) & 0xFF;
    nonce_out[1] = (boot_counter >> 16) & 0xFF;
    nonce_out[2] = (boot_counter >> 8) & 0xFF;
    nonce_out[3] = boot_counter & 0xFF;
    
    session_counter++;
    nonce_out[4] = (session_counter >> 24) & 0xFF;
    nonce_out[5] = (session_counter >> 16) & 0xFF;
    nonce_out[6] = (session_counter >> 8) & 0xFF;
    nonce_out[7] = session_counter & 0xFF;
    
    uint32_t rand_pad = esp_random();
    nonce_out[8] = (rand_pad >> 24) & 0xFF;
    nonce_out[9] = (rand_pad >> 16) & 0xFF;
    nonce_out[10] = (rand_pad >> 8) & 0xFF;
    nonce_out[11] = rand_pad & 0xFF;
}