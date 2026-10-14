"""Host client for the Tang Nano 20k crypto accelerator (framed UART protocol).

    A5 | cmd | len(2 LE) | payload | crc16(2 LE)        host -> FPGA
    5A | status | len(2 LE) | payload | crc16(2 LE)     FPGA -> host
CRC-16/CCITT-FALSE over cmd..payload (resp: status..payload).
"""
import hashlib, struct, time
import serial

OK, BAD_CMD, BAD_LEN, BAD_CRC, AUTH_FAIL, ERR, BAD_PARAM, NO_KEY = range(8)
STATUS = ["OK", "BAD_CMD", "BAD_LEN", "BAD_CRC", "AUTH_FAIL", "ERR", "BAD_PARAM", "NO_KEY"]

def crc16(data, c=0xFFFF):
    for b in data:
        c ^= b << 8
        for _ in range(8):
            c = ((c << 1) ^ 0x1021) & 0xFFFF if c & 0x8000 else (c << 1) & 0xFFFF
    return c

class AccelError(Exception):
    def __init__(self, status):
        super().__init__(f"accelerator status {status} ({STATUS[status] if status < len(STATUS) else '?'})")
        self.status = status

class Accel:
    def __init__(self, port="/dev/ttyUSB1", baud=1_500_000, timeout=5.0):
        if port == "goikey":                          # BL616 vendor bulk link (see goikey_link.py)
            from goikey_link import GoiKeyLink
            self.s = GoiKeyLink(timeout=timeout)
        else:
            self.s = serial.Serial(port, baud, timeout=timeout)
        self.s.reset_input_buffer()

    def close(self): self.s.close()

    def _read(self, n):
        d = self.s.read(n)
        if len(d) != n: raise TimeoutError(f"short read ({len(d)}/{n})")
        return d

    def call(self, cmd, payload=b"", expect_status=OK):
        body = bytes([cmd]) + struct.pack("<H", len(payload)) + payload
        self.s.write(b"\xA5" + body + struct.pack("<H", crc16(body)))
        while True:                                   # resync on SOF
            if self._read(1) == b"\x5A": break
        hdr = self._read(3)
        status, ln = hdr[0], struct.unpack("<H", hdr[1:3])[0]
        pl = self._read(ln)
        crc = struct.unpack("<H", self._read(2))[0]
        if crc != crc16(hdr + pl): raise IOError("response CRC mismatch")
        if status != expect_status: raise AccelError(status)
        return pl

    # ---- info ----
    def ping(self):
        r = self.call(0x01); return r[:8].decode(), struct.unpack(">I", r[8:12])[0]
    def uid(self): return self.call(0x02)
    def random(self, n): return self.call(0x03, struct.pack("<H", n))

    # ---- hashing ----
    def sha256(self, data): return self.call(0x10, data)
    def hmac_sha256(self, key, data):
        if len(key) > 64: key = hashlib.sha256(key).digest()      # RFC 2104
        return self.call(0x11, bytes([len(key)]) + key + data)
    def pbkdf2_sha256(self, password, salt, iters, dklen):
        if len(password) > 64: password = hashlib.sha256(password).digest()
        return self.call(0x12, struct.pack("<IHB", iters, dklen, len(password)) + password + salt)

    # ---- AES-256 ----
    def aes_set_key(self, key): self.call(0x20, key)
    def _aes(self, mode, iv, aad, data, tag=b"", expect_status=OK):
        pl = bytes([mode]) + iv.ljust(16, b"\0") + struct.pack("<HH", len(aad), len(data)) + aad + data + tag
        return self.call(0x21, pl, expect_status)
    def aes_cbc_encrypt(self, iv, data): return self._aes(2, iv, b"", data)
    def aes_cbc_decrypt(self, iv, data): return self._aes(3, iv, b"", data)
    def aes_gcm_encrypt(self, iv12, data, aad=b""):
        r = self._aes(4, iv12, aad, data); return r[:-16], r[-16:]
    def aes_gcm_decrypt(self, iv12, data, tag, aad=b""):
        return self._aes(5, iv12, aad, data, tag)


class AsymAccel(Accel):
    """Commands of the asymmetric bitstream (P-256, Ed25519, SHA-512, wrapped keys)."""
    # ---- P-256 (public keys are X||Y big-endian, signatures r||s) ----
    def p256_generate(self):
        r = self.call(0x30); return r[:64], r[64:]                   # wrapped blob, public key
    def p256_public(self, blob): return self.call(0x31, blob)
    def p256_sign(self, blob, digest32): return self.call(0x32, blob + digest32)
    def p256_ecdh(self, blob, peer_pub64): return self.call(0x33, blob + peer_pub64)
    def p256_verify(self, digest32, sig64, pub64):
        try: self.call(0x34, digest32 + sig64 + pub64); return True
        except AccelError as e:
            if e.status == AUTH_FAIL: return False
            raise
    def p256_wrap(self, raw32): return self.call(0x35, raw32)       # import an existing private key
    # ---- Ed25519 ----
    def ed25519_generate(self):
        r = self.call(0x40); return r[:64], r[64:]
    def ed25519_public(self, blob): return self.call(0x41, blob)
    def ed25519_sign(self, blob, msg): return self.call(0x42, blob + msg)
    def ed25519_wrap(self, seed32): return self.call(0x43, seed32)
    # ---- SHA-512 ----
    def sha512(self, data): return self.call(0x50, data)
    def random32(self): return self.call(0x03)


class PqAccel(Accel):
    """Commands of the ML-DSA bitstream. ps = 44, 65 or 87. Keys are wrapped blobs (nonce16 | ct | tag16)."""
    _P = {44: 0, 65: 1, 87: 2}
    SK = {44: 2560, 65: 4032, 87: 4896}
    PK = {44: 1312, 65: 1952, 87: 2592}
    SIG = {44: 2420, 65: 3309, 87: 4627}
    def blob_len(self, ps): return self.SK[ps] + 32
    def mldsa_generate(self, ps):
        r = self.call(0x60 + self._P[ps]); n = self.blob_len(ps); return r[:n], r[n:]
    def mldsa_generate_from_seed(self, ps, seed32):               # deterministic (tests only: the seed must stay secret)
        r = self.call(0x64 + self._P[ps], seed32); n = self.blob_len(ps); return r[:n], r[n:]
    def mldsa_sign(self, ps, blob, msg):
        return self.call(0x68 + self._P[ps], blob + bytes(32) + msg)
    def mldsa_sign_with_rnd(self, ps, blob, msg, rnd32):          # deterministic hedge (tests / reproducibility)
        return self.call(0x6C + self._P[ps], blob + rnd32 + msg)

class RsaAccel(PqAccel):
    """RSA-2048 commands of the pq bitstream (caps 0x700): key = wrapped CRT blob (672 bytes), e = 65537."""
    RSA_BLOB = 672
    def rsa_generate(self):
        r = self.call(0x70); return r[:self.RSA_BLOB], r[self.RSA_BLOB:]
    def rsa_public(self, blob): return self.call(0x71, blob)
    def rsa_sign_sha256(self, blob, digest32): return self.call(0x72, blob + digest32)
