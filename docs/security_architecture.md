# Security Architecture

VibedTerm implements a zero-knowledge security model where sensitive data never leaves the user's device unencrypted. This document describes the cryptographic design, trust model, and sync architecture.

## Zero-Knowledge Design

### Core Principle

**Your password never leaves your device.** VibedTerm uses a zero-knowledge architecture where:

1. The master password is used only locally to derive an encryption key
2. All encryption and decryption happens on-device
3. No server, cloud provider, or third party ever sees your plaintext credentials
4. Even with full access to your vault file, an attacker cannot recover your data without the password

### What This Means

```
┌─────────────────────────────────────────────────────────────────┐
│                        YOUR DEVICE                               │
│  ┌──────────────┐    ┌──────────────┐    ┌──────────────────┐   │
│  │   Password   │───▶│   Argon2id   │───▶│  Encryption Key  │   │
│  │  (in memory) │    │     KDF      │    │   (32 bytes)     │   │
│  └──────────────┘    └──────────────┘    └────────┬─────────┘   │
│                                                    │             │
│  ┌──────────────┐    ┌──────────────┐    ┌────────▼─────────┐   │
│  │  Plaintext   │◀──▶│  XChaCha20-  │◀──▶│   Vault File     │   │
│  │    Data      │    │  Poly1305    │    │   (encrypted)    │   │
│  └──────────────┘    └──────────────┘    └──────────────────┘   │
└─────────────────────────────────────────────────────────────────┘
                                                    │
                                                    ▼
                              ┌──────────────────────────────────┐
                              │     Cloud Storage (Optional)      │
                              │   OneDrive / Google Drive / etc.  │
                              │                                   │
                              │   Only encrypted blobs synced     │
                              │   Provider cannot read content    │
                              └──────────────────────────────────┘
```

### Trust Model

**What we trust:**
- Your device's memory during vault operations
- The cryptographic primitives (Argon2id, XChaCha20-Poly1305)
- The Dart `cryptography` package implementation

**What we explicitly do NOT trust:**
- Cloud storage providers (OneDrive, Google Drive, Dropbox)
- Network transport (all data encrypted before transmission)
- VibedTerm developers (we never receive your data)
- Any server or backend (there is none)

## Cryptographic Architecture

### Key Derivation (Argon2id)

The master password is transformed into an encryption key using Argon2id, a memory-hard key derivation function resistant to GPU/ASIC attacks:

```
Password + Salt (16 bytes random)
         │
         ▼
┌─────────────────────────────────┐
│           Argon2id              │
│  Memory:     64 MiB             │
│  Iterations: 3                  │
│  Parallelism: 1                 │
│  Output:     32 bytes           │
└─────────────────────────────────┘
         │
         ▼
   256-bit Encryption Key
```

**Why Argon2id?**
- Winner of the Password Hashing Competition (2015)
- Resistant to time-memory trade-off attacks
- Memory-hard: attackers cannot parallelize with GPUs
- Used by major password managers (Bitwarden, 1Password)

### Authenticated Encryption (AEAD)

VibedTerm uses XChaCha20-Poly1305 for authenticated encryption:

```
┌────────────────────────────────────────────────────────────────┐
│                         Vault File                              │
├────────────────────────────────────────────────────────────────┤
│  Header (unencrypted, used as AAD)                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │ Magic (VBT1) │ Version │ KDF params │ Cipher │ Nonce │ Len ││
│  └────────────────────────────────────────────────────────────┘│
├────────────────────────────────────────────────────────────────┤
│  Encrypted Payload                                              │
│  ┌────────────────────────────────────────────────────────────┐│
│  │              Ciphertext              │   Auth Tag (16B)    ││
│  │  (hosts, identities, settings, etc.) │                     ││
│  └────────────────────────────────────────────────────────────┘│
└────────────────────────────────────────────────────────────────┘
```

**Security Properties:**
- **Confidentiality**: Data encrypted with 256-bit key
- **Integrity**: Poly1305 MAC detects any tampering
- **Authenticity**: Header bound to ciphertext via AAD
- **Nonce**: 24-byte random nonce (XChaCha) prevents reuse attacks

### Cipher Options

| Cipher | Nonce | Use Case |
|--------|-------|----------|
| XChaCha20-Poly1305 | 24 bytes | Primary (software-optimized) |
| AES-256-GCM | 12 bytes | Fallback (hardware AES available) |

## Data Protection

### What's Encrypted

All sensitive data in the vault is encrypted:

| Data Type | Contents |
|-----------|----------|
| **Hosts** | Hostnames, ports, usernames, tmux settings |
| **Identities** | Private SSH keys (PEM format) |
| **Snippets** | Command snippets and scripts |
| **Settings** | App preferences, theme, SSH config |
| **Metadata** | Trusted host key fingerprints |

### What's NOT Encrypted

Only the vault file header (required for decryption):

- Magic bytes (`VBT1`)
- Format version
- KDF parameters (memory, iterations, parallelism)
- Salt (random, not secret)
- Cipher identifier
- Nonce (random, not secret)
- Payload length

**Note:** These parameters reveal nothing about vault contents and are required to derive the decryption key.

## Sync Architecture (Planned)

VibedTerm is designed for file-based sync via user-chosen cloud folders:

```
┌─────────────┐     ┌─────────────┐     ┌─────────────┐
│   Device A  │     │   Device B  │     │   Device C  │
│  (Windows)  │     │   (Linux)   │     │  (Android)  │
└──────┬──────┘     └──────┬──────┘     └──────┬──────┘
       │                   │                   │
       │ Encrypted         │ Encrypted         │ Encrypted
       │ vault file        │ vault file        │ vault file
       ▼                   ▼                   ▼
┌─────────────────────────────────────────────────────────┐
│                    Cloud Folder                          │
│              (OneDrive / Google Drive)                   │
│                                                          │
│   ~/OneDrive/VibedTerm/vault.vbt                        │
│                                                          │
│   Cloud provider syncs encrypted file                    │
│   Provider CANNOT read contents                          │
│   Provider CANNOT recover password                       │
└─────────────────────────────────────────────────────────┘
```

### Conflict Resolution

Each vault tracks:
- `revision`: Incremented on each save
- `deviceId`: UUID of the writing device
- `updatedAt`: Timestamp of last modification

When conflicts occur (same revision, different deviceId), the user is prompted to resolve.

### No Backend Server

VibedTerm has **no backend server**. Benefits:

- No account creation required
- No data collection
- No server to compromise
- No subscription fees
- Works fully offline
- User controls their data location

## Auto-Unlock Security

VibedTerm optionally stores the vault password for auto-unlock:

```
┌─────────────────────────────────────────────────────────────────┐
│                     Platform Keychain                            │
│                                                                  │
│   Windows: Windows Credential Manager (DPAPI)                    │
│   Linux:   libsecret / GNOME Keyring                            │
│   Android: EncryptedSharedPreferences (Keystore-backed)         │
│                                                                  │
│   Password encrypted with hardware-backed key where available   │
└─────────────────────────────────────────────────────────────────┘
```

**Trade-off:** Convenience vs. security. Users who disable auto-unlock must enter their password each time, but the password is never persisted.

## Security Considerations

### Password Strength

The vault's security depends on password strength:

| Password Type | Entropy | Brute Force (Argon2id @ 64MB) |
|--------------|---------|-------------------------------|
| 4 digits | ~13 bits | Seconds |
| 8 lowercase | ~38 bits | Days |
| 12 mixed + symbols | ~72 bits | Centuries |
| Passphrase (4 words) | ~44 bits | Years |

**Recommendation:** Use a passphrase of 4+ random words or 12+ character password with mixed case, numbers, and symbols.

### Known Limitations

1. **Memory exposure**: Decrypted data exists in RAM during use
2. **Clipboard**: Pasted passwords may remain in clipboard history
3. **Screen capture**: Terminal content visible if device compromised
4. **Key extraction**: Attacker with device access could extract auto-unlock password

### Mitigations

- Vault auto-locks after configurable timeout (planned)
- Clipboard auto-clear after paste (planned)
- Memory is released when vault locks
- Auto-unlock can be disabled for maximum security

## Comparison with Other Solutions

| Feature | VibedTerm | Termius | MobaXterm | Bitwarden |
|---------|-----------|---------|-----------|-----------|
| Zero-knowledge | Yes | No (cloud sync) | No (local only) | Yes |
| Open source | Yes | No | No | Yes |
| Offline-first | Yes | Partial | Yes | Partial |
| No account required | Yes | No | Yes | No |
| E2E encrypted sync | Yes | Unknown | No | Yes |
| Self-hosted option | N/A (no server) | No | N/A | Yes |

## Further Reading

- [Vault Specification v1](vault_spec_v1.md) - Detailed file format
- [Argon2 RFC 9106](https://www.rfc-editor.org/rfc/rfc9106.html) - KDF specification
- [XChaCha20-Poly1305](https://datatracker.ietf.org/doc/html/draft-irtf-cfrg-xchacha) - AEAD cipher
