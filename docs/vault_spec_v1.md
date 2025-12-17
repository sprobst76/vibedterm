# VibedTerm Vault Specification — v1

Guidance for the initial vault format used by `core_vault`. Scope is “vault file in a sync folder” with strong encryption and versioning.

## Goals

- Offline-first single-file vault suitable for OneDrive/Drive folder sync.
- Strong encryption with modern KDF; tamper detection via AEAD tag.
- Clear versioning to allow future migrations.
- Deterministic, testable format with reproducible vectors once crypto is wired.

## File Layout

```
[ header ][ ciphertext_with_tag ]
```

Header fields (little-endian for numeric values):

| Offset | Size | Field | Notes |
| --- | --- | --- | --- |
| 0 | 4 | Magic | ASCII `VBT1` |
| 4 | 1 | Version | `0x01` |
| 5 | 1 | KDF id | `0x01` = Argon2id, `0x02` = scrypt (fallback) |
| 6 | 4 | KDF memory_kib | e.g., 65536 (64 MiB) |
| 10 | 4 | KDF iterations | e.g., 3 for Argon2id |
| 14 | 4 | KDF parallelism | e.g., 1–2 |
| 18 | 16 | KDF salt | 16-byte random |
| 34 | 1 | Cipher id | `0x01` = XChaCha20-Poly1305, `0x02` = AES-256-GCM |
| 35 | 1 | Nonce length | 24 for XChaCha, 12 for GCM |
| 36 | var | Nonce | Length per field above |
| 36+N | 4 | Payload length | uint32 of plaintext bytes |

Ciphertext with tag immediately follows; AEAD tag is appended by the cipher (16 bytes for both recommended modes).

## Crypto Choices

- **Preferred cipher:** XChaCha20-Poly1305 (`cipher id 0x01`, `nonce len 24`). AES-256-GCM allowed if XChaCha is not available on a platform.
- **KDF:** Argon2id with defaults: memory 64 MiB, iterations 3, parallelism 1. Allow per-vault overrides stored in header. Scrypt (`kdf id 0x02`) only if Argon2 is not available.
- **Derived key:** 32 bytes from the KDF.
- **Associated data (AAD):** the full header bytes (from offset 0 through the payload length field) to bind parameters.

## Payload (plaintext before encryption)

JSON or CBOR object (JSON is fine for v1):

```json
{
  "version": 1,
"revision": 1,
"deviceId": "<uuid>",
"createdAt": "<iso8601>",
"updatedAt": "<iso8601>",
"hosts": [ /* host objects */ ],
"identities": [ /* keys */ ],
  "snippets": [ /* optional */ ],
  "settings": { /* app prefs */ },
  "meta": { "notes": "optional" }
}
```

`revision` increments on each save; `deviceId` identifies the writer to help conflict detection later.

## Create Flow

1. Collect password.
2. Generate random salt (16 bytes) and nonce (24 for XChaCha or 12 for GCM).
3. Derive 32-byte key via Argon2id with header-stored params.
4. Serialize payload to UTF-8 bytes (JSON/CBOR) and record its length.
5. Build header with fields above.
6. Encrypt payload with chosen cipher using nonce, key, and header as AAD; append tag.
7. Write header + ciphertext+tag to the vault file atomically (temp file + rename).

## Open/Verify Flow

1. Read header, validate magic/version.
2. Parse KDF/cipher/nonce/payload length; read ciphertext+tag.
3. Derive key using stored KDF params and provided password.
4. Decrypt using stored cipher/nonce and header as AAD.
5. Verify AEAD tag; on failure return a consistent “invalid password or corrupted vault” error.
6. Parse payload into in-memory models.

## Error Handling

- Wrong password or tampering: fail decryption and surface a single generic error string to avoid oracle hints.
- Unsupported version/KDF/cipher: explicit error and refuse to open.
- Payload length sanity checks to avoid allocation abuse (e.g., cap at 16 MiB by default and allow override).

## Reference Inputs for Future Test Vector

When crypto libs are available, generate and record a canonical vector using:

- Password: `correct horse battery staple`
- Salt (hex): `0a8f0c5e2b6f4d8897a3c1d2e4f6b8c9`
- Nonce (XChaCha, hex): `1f2e3d4c5b6a79888796a5b4c3d2e1f0ffeeddccbbaa`
- KDF params: Argon2id, memory=65536 KiB, iterations=3, parallelism=1
- Payload JSON: `{"version":1,"revision":1,"deviceId":"00000000-0000-4000-8000-000000000000","createdAt":"2024-01-01T00:00:00Z","updatedAt":"2024-01-01T00:00:00Z","hosts":[],"identities":[],"snippets":[],"settings":{},"meta":{}}`

Record the derived key, ciphertext, and full vault hex once computed to lock in regression tests for roundtrips and tamper detection.
