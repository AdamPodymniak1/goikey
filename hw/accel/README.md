# Tang Nano 20k crypto accelerator

FPGA offload for the cryptographic algorithms of this project. The ESP32 talks to it over **SPI** (production) or a
framed **UART** (bring-up / host tests); when no FPGA answers, the firmware computes everything itself.
Everything here is verified against independent references (`hashlib`, `cryptography`, the PQClean sources in `lib/`)
in simulation (Icarus Verilog). On the board, the earlier `sym`/`asym`/`pq` builds passed all self-tests; the current
`main`/`sym` (ECC on the shared engine, RAM-based SHA-512, lane-serial Keccak) have **not been re-run on hardware yet**,
and neither has the SPI link to the ESP32.

## Bitstreams (the GW2AR-18C holds one at a time)

| profile | build | contents | LUT4 | BSRAM | caps |
|---|---|---|---|---|---|
| **`main`** | `./hw/accel/build_accel.sh main` | **all key operations in one bitstream**: P-256 (keygen, ECDSA sign/verify, ECDH), Ed25519, ML-DSA-44/65/87 (keygen, sign), RSA-2048 (keygen, RS256 sign), SHA-512, TRNG, UID, wrapped-key store | 68 % | 44/46 | `0x7F0` |
| `sym`  | `./hw/accel/build_accel.sh sym`  | SHA-256, HMAC-SHA256, PBKDF2-HMAC-SHA256, AES-256 CBC and GCM, TRNG, UID | 50 % | 10/46 | `0x00F` |
| `asym` / `pq` | `build_accel.sh asym` / `pq` | the two halves of `main` on their own (smaller, used for debugging) | 31 % / 49 % | 18 / 39 | `0x0F0` / `0x700` |
| `full`, `all` | `build_accel.sh full` / `all` | `main` + SHA-256/HMAC/PBKDF2 (+ AES) - **do not place & route** (see below) | 82 % / >100 % | | |

Everything except AES / SHA-256 / HMAC / PBKDF2 lives in `main`; the firmware (`src/CryptoAccel.cpp`) offloads whatever the
loaded bitstream advertises in its `ping` capability word and computes the rest on the ESP32 (which has hardware AES/SHA
anyway). Load `sym` instead when you want PBKDF2 (200 000 iterations: 1.7 s) or bulk AES on the FPGA.

Build and flash (inside `nix-shell`; place & route takes a few minutes):

    nix-shell --run './hw/accel/build_accel.sh main'
    nix-shell --run 'openFPGALoader -b tangnano20k hw/accel/build/accel_main.fs'      # SRAM, volatile
    nix-shell --run 'for t in asym pq rsa; do python3 hw/accel/host/selftest_$t.py /dev/ttyUSB1; done'

(`sym` -> `selftest.py`). The USB debugger exposes two ports; the accelerator UART is `/dev/ttyUSB1` (needs the udev rule
in `hw/tro/99-tangnano20k.rules`). `openFPGALoader -f` writes the bitstream to flash. `SYNTH_OPTS=-nowidelut` is what the
numbers above were built with (it avoids wide-LUT mux leaves and is markedly smaller); set `SYNTH_ONLY=1` to just synthesize.

### Why not one bitstream with everything?
`main` already uses 68 % of the LUT4 sites and 44 of 46 block RAMs. The device's place & route stops working somewhere
between 68 % and 82 % for this kind of design (many carry chains): `main` + the compact SHA-256/HMAC/PBKDF2 unit is 17.1k LUT4
(82 %, `build_accel.sh full`) and nextpnr reports *"Unable to find legal placement"*; AES alone would add ~5k LUT4. What was
done to get here (all measured): lane-serial Keccak with 5-lane shift rings (4.1k -> 1.3k LUT), SHA-512 on a RAM-based serial
datapath (3.5k -> 1.8k), P-256/Ed25519 field arithmetic moved onto the RSA Montgomery engine (the old register-array
`modalu` was 3.6k LUT), byte-serial AES (2.3k -> 2.0k core), a RAM-based SHA-256/HMAC/PBKDF2 unit (5.1k -> 2.1k), ML-DSA
`w1` packed in scratch instead of K polynomial slots (-5 block RAMs). Further reductions need a rewrite of the polynomial
engine or of the command sequencers (unifying `ecc_seq`, `pq_seq`, `accel_cmd` into one microcoded machine) - not done.

## Wire protocol (UART 8N1, 1.5 Mbaud; SPI mode 0 carries the same frames)

    host -> FPGA : A5 | cmd | len (2 LE) | payload | crc16 (2 LE)
    FPGA -> host : 5A | status | len (2 LE) | payload | crc16 (2 LE)

CRC-16/CCITT-FALSE (poly 0x1021, init 0xFFFF) over `cmd..payload` / `status..payload`. Payload <= 8 KiB.
Status: 0 OK, 1 BAD_CMD, 2 BAD_LEN, 3 BAD_CRC, 4 AUTH_FAIL, 5 ERR, 6 BAD_PARAM, 7 NO_KEY. One request in flight at a time.
Commands of a unit that is not in the loaded bitstream return BAD_CMD. Clients: `host/tro_accel.py` (Python),
`include/FpgaAccel.h` + `src/FpgaAccel.cpp` (ESP32, SPI or UART).

SPI: the FPGA is a mode-0 slave (SCK <= ~4 MHz); the reply goes back on the transport on which the request started. Pins
(assumed header pins, **verify against your wiring**, `accel.cst`): FPGA 25 = SCK, 26 = MOSI, 27 = CS_N, 28 = MISO;
ESP32 defaults SCK 14, MOSI 15, MISO 21, CS 18 (override with `-D FPGA_PIN_SCK=..` etc.).

### Info (every bitstream)
`0x01` ping -> `"TROACC01"` + caps(4)  |  `0x02` UID (16 B)  |  `0x03` 32 random bytes (TRNG; `sym` only: payload n LE16, n bytes)
caps bits: `0x07` SHA-256/HMAC/PBKDF2, `0x08` AES, `0xF0` P-256/Ed25519/SHA-512, `0x300` ML-DSA, `0x400` RSA-2048.

### `sym`
| cmd | payload | response |
|---|---|---|
| 0x10 | data | SHA-256 |
| 0x11 | klen(1) key(<=64) data | HMAC-SHA256 |
| 0x12 | iters(4 LE) dklen(2 LE) pwlen(1) pw(<=64) salt | PBKDF2-HMAC-SHA256, dklen <= 1024 (226 clk per iteration: 200 000 iterations = 1.7 s) |
| 0x20 | key(32) | - (AES-256 key) |
| 0x21 | mode(1) iv(16) aadlen(2) dlen(2) aad data [tag(16) if mode 5] | data (+tag for mode 4); mode 0/1 ECB, 2/3 CBC, 4/5 GCM (12-byte IV); a failed GCM tag returns AUTH_FAIL and **no plaintext** |

### Key operations (`main`) - private keys exist only as wrapped blobs
P-256 / Ed25519 blobs are `nonce(16) | ct(32) | tag(16)`: `ct = secret xor HMAC-SHA512(MASTER,'E'|nonce)[0:32]`,
`tag = HMAC-SHA512(MASTER,'M'|nonce|ct)[0:16]`. ML-DSA and RSA blobs are `nonce(16) | ct | tag(16)` with a SHAKE256
keystream / MAC (`SHAKE256('E'|MASTER|nonce)`, tag over `'M'|MASTER|nonce|ct`). `MASTER` is a per-device 256-bit random value
generated at first build (`hw/tro/build/master.hex`) and baked into the bitstream. Keep blobs in NVS in place of ATECC slots.

| cmd | payload | response |
|---|---|---|
| 0x30 | - | blob(64) pub X\|Y(64) - P-256 keygen |
| 0x31 | blob | pub(64) |
| 0x32 | blob digest(32) | r\|s (64) - ECDSA, nonce from the TRNG |
| 0x33 | blob peerX\|Y(64) | shared x (32) - ECDH (peer point is validated) |
| 0x34 | digest r s X Y (160 B) | OK / AUTH_FAIL - ECDSA verify |
| 0x35 | raw d(32) | blob - import an existing P-256 key |
| 0x40 | - | blob(64) pub(32) - Ed25519 keygen |
| 0x41 / 0x42 | blob / blob msg | pub(32) / signature(64) (identical to RFC 8032) |
| 0x43 | seed(32) | blob |
| 0x50 | data | SHA-512 |
| 0x60+p / 0x64+p | - / seed(32) | blob \| public key - ML-DSA keygen (p = 0, 1, 2 -> ML-DSA-44, 65, 87; TRNG seed / given seed) |
| 0x68+p / 0x6C+p | blob \| 32 zero bytes \| msg / blob \| rnd(32) \| msg | signature (hedged with the TRNG / explicit randomness); bad blob tag -> AUTH_FAIL |
| 0x70 | - | blob(672) \| n(256) - RSA-2048 keygen (e = 65537, two 1024-bit primes with the top two bits set; typically 10-60 s) |
| 0x71 | blob | n(256) |
| 0x72 | blob \| SHA-256 digest(32) | 256-byte RSASSA-PKCS1-v1_5 signature (CRT with a fault check, ~1 s) |

Sizes: ML-DSA blob = nonce + sk + tag = 2592 / 4064 / 4928 bytes (`host/tro_accel.py: blob_len`), public keys 1312 / 1952 / 2592,
signatures 2420 / 3309 / 4627. Timings (27 MHz, simulation cycle counts; ML-DSA/RSA also measured on the board): P-256 keygen / sign 0.40 / 0.42 s,
verify 0.80 s, ECDH 0.40 s; Ed25519 sign 0.44 s; ML-DSA-44 keygen 0.08 s, sign ~0.1-1 s (rejection sampling), ML-DSA-87 sign up to ~1.5 s;
RSA keygen 13.6 s (measured, one sample), sign ~1 s.

## Architecture
* `rtl/accel_top.v` - UART + SPI link (`uart.v`, `spi_slave.v`, `frame_io.v`: CRC, 8 KiB RX/TX RAM), TRNG + UID (`tro_lite.v`),
  command-class routing (0x1_/0x2_ symmetric, 0x3_-0x5_ ECC, 0x6_/0x7_ ML-DSA/RSA, 0x0_ info), the shared **bignum engine** and one
  command processor per unit. Parameters `HAS_SYM`, `HAS_AES`, `HAS_ECC`, `HAS_PQ` select the profile.
* `rtl_pq/bn_engine.v` - 16-bit-limb pipelined Montgomery engine (one word per clock, DSP multipliers) with a 2048 x 16-bit
  register file in block RAM. RSA mode: 64-limb registers, ops `RMSEL RR2 RMUL RADDM RSUBM RCSUB REXP RSIEVE RREM1 RMULF RKINV RDP ...`
  driven by the ML-DSA sequencer. ECC mode: 16-limb registers (128 of them), MUL/ADD/SUB/LT/XOR/AND/OR/BSWAP with the P-256 p/n and
  Ed25519 p/l moduli, driven by `ecc_seq`. The same RAM is the register file of both, so ECC and RSA time-share it.
* `rtl/ecc_seq.v` + `ref/ecc_asm.py` - the whole ECC command layer is **microcode** (`rtl/ecc_ucode.vh`); `hash512_unit.v` is a RAM-based serial
  SHA-512; P-256 uses the Renes-Costello-Batina complete formulas, both curves run a fixed double-and-add-always sequence.
* `rtl_pq/pq_*.v` + `ref/pq/pq_asm.py` - ML-DSA: sequencer (`pq_seq`), polynomial engine (NTT, pointwise, rounding, hints), samplers, bit packers,
  byte unit, SHAKE (`rtl/keccak_core.v`, `shake_unit.v`). The microcode ROM image holds the keygen/sign programs for all three parameter sets and the
  RSA programs (keygen: prime search with sieve + Euler tests, CRT parameters; sign: PKCS#1 v1.5 + CRT + fault check).
* `rtl/hash_unit.v` (SHA-256/HMAC/PBKDF2 over one block RAM and a one-round-per-clock compressor), `rtl/aes_core.v`/`aes_modes.v`/`ghash_mul.v`
  (byte-serial AES, CBC/GCM), `accel_cmd.v` / `hash_cmd.v` (command flows).
* Reference models used as oracles: `ref/ecc_model.py`, `ref/pq/pq_model.py` (bit-exact vs the C sources), `ref/pq/rsa_model.py`, the ISA interpreters in `ref/ecc_asm.py` and `ref/pq/pq_asm.py`.
* Lessons learned on this FPGA: multiplications by constants or small multipliers inferred into DSP blocks misbehave (use shift-add / tables);
  BSRAM read data is usable two clocks after the address; `synth_gowin -nowidelut` shrinks mux-heavy logic a lot; LUT4 occupancy above ~70-80 %
  with many ALU carry chains fails to legalise.

## Firmware integration (ESP32)
`include/FpgaAccel.h` / `src/FpgaAccel.cpp` (transport, framing, one wrapper per command, capability probing, mutex around the link, re-probe every few
seconds after a failure) and `include/CryptoAccel.h` / `src/CryptoAccel.cpp` (policy layer: offload only when it pays, otherwise mbedTLS):
SHA-256/HMAC (>= 1 KiB), PBKDF2 (>= 1000 iterations), AES CBC/GCM (>= 256 B), FPGA TRNG mixed into `secureFillRandom`. FIDO credential keys are
generated inside the FPGA when the `asym` unit is present (`generateCredentialKeyP256`, Ed25519, `generateRsa2048KeyPair`, `generateMlDsaKeyPairEx`):
the stored "private key" is then the wrapped blob (128 hex characters for P-256/Ed25519, 1344 for RSA, sk+32 bytes for ML-DSA) and signing goes back to the FPGA;
existing software keys keep working. If the FPGA is absent or does not answer, key generation falls back to software keys; a blob cannot be used without the
FPGA that wrapped it.

## Tests (run inside `nix-shell`)
    # unit level
    cd hw/accel
    python3 ref/gen_tb_hash.py && iverilog -g2012 -Irtl -o /tmp/t tb/tb_hash_unit.v rtl/hash_unit.v && vvp /tmp/t          # SHA-256/HMAC/PBKDF2
    iverilog -g2012 -Irtl -o /tmp/t tb/tb_sha512.v rtl/hash512_unit.v && vvp /tmp/t                                      # SHA-512 (also tb_sha512b: back-to-back bytes)
    iverilog -g2012 -Irtl -o /tmp/t tb/tb_aes_core.v rtl/aes_core.v && vvp /tmp/t                                        # AES (and tb_aes_modes.v)
    iverilog -g2012 -Irtl -o /tmp/t tb/tb_keccak.v rtl/keccak_core.v && vvp /tmp/t                                       # Keccak (and tb_shake.v)
    ref/pq/build_ref.sh                                                                                         # once: build the PQClean golden/verify helpers
    python3 ref/pq/pq_asm.py                                                                                              # ML-DSA programs vs the C reference + info commands
    python3 ref/pq/tb_rsa_ops.py 1                                                                                        # every bignum-engine op vs the interpreter (RTL in iverilog)
    python3 ref/pq/gen_tb_core.py 44 both && iverilog ... tb/tb_pq_core.v rtl_pq/*.v ... && vvp ... +vec=tb/vec_pq        # ML-DSA through the core (44/65/87)
    python3 ref/pq/gen_tb_rsa.py && ... +vec=tb/vec_rsa                                                                   # RSA pub/sign through the core
    ... +vec=tb/vec_rsagen +dump && python3 ref/pq/check_rsagen.py tb/vec_rsagen/got_0.hex                               # RSA keygen through the core (slow, ~hours)
    iverilog -g2012 -Irtl -Irtl_pq -o /tmp/t tb/tb_ecc_seq.v rtl/ecc_seq.v rtl_pq/bn_engine.v && vvp /tmp/t               # ECC microcode on the shared engine
    # link level (frames over the UART model), per profile
    python3 ref/gen_vec_link.py && iverilog -g2012 -DSIM_FAST_TRNG -Irtl -Irtl_pq -Ptb_accel_top.HAS_AES=1 -o /tmp/a rtl/*.v rtl_pq/bn_engine.v tb/tb_accel_top.v && vvp /tmp/a +VEC=tb/vec            # sym
    python3 ref/gen_vec_ecc.py tb/vec_ecc && ... -Ptb_accel_top.HAS_AES=0 -Ptb_accel_top.HAS_ECC=1 ... +VEC=tb/vec_ecc                                                                 # asym (a few minutes per P-256 op)
    PQ_CAPS=0x7F0 python3 ref/pq/pq_asm.py && python3 ref/gen_vec_main.py tb/vec_main && ... -Ptb_accel_top.HAS_ECC=1 -Ptb_accel_top.HAS_PQ=1 ... +VEC=tb/vec_main       # main: class routing + one command per unit
    # on the board
    python3 host/selftest.py | selftest_asym.py | selftest_pq.py | selftest_rsa.py /dev/ttyUSB1

## Security notes - read before replacing the ATECC
* **No tamper resistance.** The ATECC608 keeps keys in a hardened, access-controlled store. Here the wrapping key
  `MASTER` lives in the bitstream; whoever can read the FPGA configuration flash (or the file under `build/`) can
  unwrap every blob. Gowin bitstream encryption / read-back protection is **not** configured here.
* The TRNG (ring oscillators, XOR + von Neumann) passes basic statistical tests but is not NIST SP 800-90B validated.
  ECDSA nonces and all generated keys come from it; if that matters to you, mix in another entropy source as `CryptoManager` does today.
* The microprograms run a fixed instruction sequence independent of secret values (no secret-dependent branches or addresses;
  the RSA/ECC exponent loops always do the multiply), but no power / EM side-channel hardening was attempted. RSA/ML-DSA/ECC keys do
  pass through ESP32 RAM only in the import paths (`0x35`, `0x43`).
* `hw/tro/build/master.hex` and `uid.hex` are per-device secrets: they are git-ignored; back them up if you need to
  rebuild a bitstream that can still unwrap existing blobs.
* A powered-off or re-flashed board loses the SRAM bitstream; blobs stay valid as long as `MASTER` is unchanged.
* Credentials created while the FPGA is attached are stored as wrapped blobs and are **bound to that board's `MASTER`**:
  without it (FPGA missing, different board, `MASTER` lost) they cannot sign, and an encrypted backup restores
  blobs, not usable keys. The firmware never silently falls back for such a credential; it logs an error and fails.
  New credentials are created as software keys while no FPGA answers.
