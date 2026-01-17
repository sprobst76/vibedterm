# VibedTerm Server Architecture Plan

## Übersicht

Dieses Dokument beschreibt die geplante Server-Architektur für VibedTerm, die eine sichere Cloud-Synchronisation des Vaults ermöglicht, während das Zero-Knowledge-Prinzip vollständig gewahrt bleibt.

---

## Inhaltsverzeichnis

1. [Architektur-Übersicht](#architektur-übersicht)
2. [Zero-Knowledge Design](#zero-knowledge-design)
3. [Authentifizierung & 2FA](#authentifizierung--2fa)
4. [Vault-Synchronisation](#vault-synchronisation)
5. [Web-Interface](#web-interface)
6. [API-Design](#api-design)
7. [Datenbank-Schema](#datenbank-schema)
8. [Sicherheitsmaßnahmen](#sicherheitsmaßnahmen)
9. [Technologie-Stack](#technologie-stack)
10. [Implementierungs-Phasen](#implementierungs-phasen)

---

## Architektur-Übersicht

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                        VIBEDTERM CLOUD ARCHITECTURE                         │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐        │
│  │  Windows    │  │   Linux     │  │  Android    │  │    Web      │        │
│  │    App      │  │    App      │  │    App      │  │  Interface  │        │
│  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘  └──────┬──────┘        │
│         │                │                │                │               │
│         └────────────────┴────────────────┴────────────────┘               │
│                                   │                                         │
│                                   │ HTTPS/TLS 1.3                          │
│                                   │                                         │
│                                   ▼                                         │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         API GATEWAY (Caddy)                           │  │
│  │  • TLS Termination  • Rate Limiting  • CORS  • Security Headers      │  │
│  └───────────────────────────────┬──────────────────────────────────────┘  │
│                                  │                                          │
│                                  ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                      APPLICATION SERVER (Go/Gin)                      │  │
│  │                                                                       │  │
│  │  ┌─────────────┐  ┌─────────────┐  ┌─────────────┐  ┌────────────┐  │  │
│  │  │    Auth     │  │    Sync     │  │   Device    │  │   Admin    │  │  │
│  │  │   Handler   │  │   Handler   │  │   Handler   │  │  Handler   │  │  │
│  │  └─────────────┘  └─────────────┘  └─────────────┘  └────────────┘  │  │
│  │                                                                       │  │
│  │  ┌─────────────────────────────────────────────────────────────────┐ │  │
│  │  │                      Middleware Layer                           │ │  │
│  │  │  • JWT Validation  • Rate Limiting  • Logging  • TOTP Check    │ │  │
│  │  └─────────────────────────────────────────────────────────────────┘ │  │
│  └───────────────────────────────┬──────────────────────────────────────┘  │
│                                  │                                          │
│                                  ▼                                          │
│  ┌──────────────────────────────────────────────────────────────────────┐  │
│  │                         PostgreSQL Database                           │  │
│  │                                                                       │  │
│  │   users          devices        encrypted_vaults     sync_logs       │  │
│  │   ├── id         ├── id         ├── id               ├── id          │  │
│  │   ├── email      ├── user_id    ├── user_id          ├── user_id     │  │
│  │   ├── pw_hash    ├── name       ├── vault_blob ◄──── │  ├── device_id │  │
│  │   ├── totp_*     ├── type       ├── nonce      │     ├── action     │  │
│  │   └── ...        └── ...        ├── revision    │     └── ...        │  │
│  │                                 └── updated_at ─┘                     │  │
│  └──────────────────────────────────────────────────────────────────────┘  │
│                                                                             │
│  ZERO-KNOWLEDGE GARANTIE:                                                  │
│  ═══════════════════════                                                   │
│  • Server speichert NUR verschlüsselte Blobs                               │
│  • Vault-Passwort wird NIEMALS übertragen                                  │
│  • Entschlüsselung erfolgt AUSSCHLIESSLICH auf dem Client                 │
│  • Selbst bei Server-Kompromittierung sind Daten unlesbar                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Zero-Knowledge Design

### Zwei-Ebenen-Verschlüsselung

VibedTerm verwendet eine **doppelte Verschlüsselungsebene**:

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      ZWEI-EBENEN VERSCHLÜSSELUNG                            │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  EBENE 1: Vault-Verschlüsselung (lokal, existiert bereits)                 │
│  ═════════════════════════════════════════════════════════                 │
│                                                                             │
│  Vault-Passwort ──► Argon2id (64MB, 3 iter) ──► 256-bit Key                │
│                                                    │                        │
│  Plaintext ◄──────── XChaCha20-Poly1305 ◄─────────┘                        │
│  (hosts, keys,                    │                                         │
│   settings)                       ▼                                         │
│                            ┌──────────────┐                                 │
│                            │  Vault File  │                                 │
│                            │  (encrypted) │                                 │
│                            └───────┬──────┘                                 │
│                                    │                                        │
│  EBENE 2: Transport/Storage-Verschlüsselung (neu für Sync)                 │
│  ═════════════════════════════════════════════════════════                 │
│                                    │                                        │
│  Account-Passwort ──► PBKDF2 ──► Verification Hash (Server speichert)      │
│        │                                                                    │
│        │                 ┌─────────────────────────────────────────────┐   │
│        │                 │  Vault-Datei ist bereits verschlüsselt!     │   │
│        │                 │  Kann direkt als Blob gespeichert werden    │   │
│        │                 └─────────────────────────────────────────────┘   │
│        │                                                                    │
│        ▼                                                                    │
│  Server Auth ──────────► Upload encrypted vault blob ──────► PostgreSQL   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Was der Server speichert vs. was er NICHT kennt

| Server speichert | Server kennt NICHT |
|------------------|-------------------|
| E-Mail-Adresse | Vault-Passwort |
| Account-Passwort-Hash (bcrypt) | Vault-Encryption-Key |
| Verschlüsselter Vault-Blob | SSH-Hosts |
| Vault-Revision | SSH-Private-Keys |
| Geräteinformationen | SSH-Passwörter |
| Sync-Zeitstempel | Einstellungen |

### Vault-Passwort vs. Account-Passwort

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                    PASSWORT-TRENNUNG                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  ACCOUNT-PASSWORT                    VAULT-PASSWORT                         │
│  ════════════════                    ═══════════════                        │
│                                                                             │
│  • Für Server-Authentifizierung      • Für Vault-Entschlüsselung           │
│  • Hash wird auf Server gespeichert  • Wird NIEMALS übertragen             │
│  • Kann zurückgesetzt werden         • Bei Verlust: Daten verloren!        │
│  • Mit 2FA geschützt                 • Lokale Sicherheit                    │
│                                                                             │
│  ┌─────────────────┐                 ┌─────────────────┐                   │
│  │ server@email.de │                 │ MyVaultPass123! │                   │
│  │ + 2FA TOTP      │                 │                 │                   │
│  └────────┬────────┘                 └────────┬────────┘                   │
│           │                                   │                             │
│           ▼                                   ▼                             │
│  ┌─────────────────┐                 ┌─────────────────┐                   │
│  │ Server-Zugang   │                 │ Vault öffnen    │                   │
│  │ (Cloud Sync)    │                 │ (Daten lesen)   │                   │
│  └─────────────────┘                 └─────────────────┘                   │
│                                                                             │
│  OPTION: Gleiche Passwörter verwenden (Komfort vs. Sicherheit)             │
│  ─────────────────────────────────────────────────────────────             │
│  • Möglich, aber nicht empfohlen                                           │
│  • Bei Server-Kompromittierung: Account-Passwort gefährdet                 │
│  • Vault bleibt trotzdem sicher (andere KDF, anderer Salt)                 │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Authentifizierung & 2FA

### Login-Flow

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         AUTHENTIFIZIERUNGS-FLOW                             │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  CLIENT                                    SERVER                           │
│  ══════                                    ══════                           │
│                                                                             │
│  1. E-Mail + Account-Passwort ─────────────► bcrypt.Compare()              │
│                                                     │                       │
│                                    ┌────────────────┴────────────────┐     │
│                                    │      2FA aktiviert?             │     │
│                                    └───────┬──────────────┬──────────┘     │
│                                            │              │                 │
│                                         JA │              │ NEIN           │
│                                            ▼              │                 │
│  2. ◄──────────────────────── requires_totp: true        │                 │
│                               temp_token: "..."           │                 │
│                                            │              │                 │
│  3. TOTP-Code (6 Ziffern) ─────────────────►              │                 │
│                                            │              │                 │
│                                            ▼              ▼                 │
│  4. ◄───────────────────────────────── JWT Tokens                          │
│     {                                                                       │
│       access_token: "...",    (15 min gültig)                              │
│       refresh_token: "...",   (30 Tage gültig)                             │
│       device_id: "..."                                                      │
│     }                                                                       │
│                                                                             │
│  5. Access Token in Authorization Header für alle API-Calls               │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### 2FA-Optionen

| Methode | Beschreibung | Empfehlung |
|---------|--------------|------------|
| **TOTP** | Time-based OTP (Authenticator App) | Standard |
| **WebAuthn/Passkey** | Hardware-Schlüssel, Biometrie | Geplant (Phase 2) |
| **Recovery Codes** | 8 Einmal-Codes für Notfall | Immer generiert |

### TOTP-Einrichtung

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                           TOTP SETUP                                        │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  1. User aktiviert 2FA in Einstellungen                                    │
│                                                                             │
│  2. Server generiert:                                                       │
│     • TOTP Secret (160 bit, Base32)                                        │
│     • QR-Code URL für Authenticator                                        │
│                                                                             │
│  3. User scannt QR-Code mit Authenticator App                              │
│     (Google Authenticator, Authy, 1Password, etc.)                         │
│                                                                             │
│  4. User bestätigt mit erstem TOTP-Code                                    │
│                                                                             │
│  5. Server aktiviert TOTP und generiert Recovery Codes                     │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        RECOVERY CODES                               │   │
│  │                                                                     │   │
│  │   ABCD-EFGH-IJKL    MNOP-QRST-UVWX    1234-5678-90AB              │   │
│  │   CDEF-GHIJ-KLMN    OPQR-STUV-WXYZ    3456-7890-ABCD              │   │
│  │                                                                     │   │
│  │   ⚠️  Diese Codes sicher aufbewahren!                              │   │
│  │   Jeder Code kann nur EINMAL verwendet werden.                     │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Vault-Synchronisation

### Sync-Strategie: Revision-basiert

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      VAULT SYNC STRATEGIE                                   │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Jeder Vault hat:                                                          │
│  • revision: Inkrementiert bei jedem Speichern                             │
│  • deviceId: UUID des schreibenden Geräts                                  │
│  • updatedAt: Zeitstempel der letzten Änderung                             │
│                                                                             │
│  SYNC-FLOW:                                                                 │
│                                                                             │
│  Device A                   Server                    Device B              │
│  ═════════                  ══════                    ═════════             │
│                                                                             │
│  1. Vault öffnen                                                            │
│     revision: 5                                                             │
│                                                                             │
│  2. ──── GET /sync/vault ────►                                             │
│          since: 5                                                           │
│                                                                             │
│  3. ◄─── revision: 5 (no changes) ───                                      │
│                                                                             │
│  4. User ändert Host...                                                     │
│     revision: 6                                                             │
│                                                                             │
│  5. ──── POST /sync/vault ───►                                             │
│          blob: "...",                                                       │
│          revision: 6                                                        │
│                                                                             │
│                             6. Server speichert      7. ◄── Push Notification │
│                                                         (oder Polling)      │
│                                                                             │
│                                                      8. GET /sync/vault    │
│                                                         since: 5           │
│                                                                             │
│                             9. ────────────────────► revision: 6, blob     │
│                                                                             │
│                                                      10. Vault aktualisieren│
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Konflikt-Erkennung

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      KONFLIKT-HANDLING                                      │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  SZENARIO: Zwei Geräte bearbeiten gleichzeitig                             │
│                                                                             │
│  Device A (revision 5)              Device B (revision 5)                  │
│  ─────────────────────              ─────────────────────                  │
│                                                                             │
│  1. Offline, ändert Host            2. Offline, ändert anderer Host        │
│     revision → 6                       revision → 6                         │
│                                                                             │
│  3. Online, pusht ────────────────► Server akzeptiert (6 > 5)              │
│                                     Server revision = 6                     │
│                                                                             │
│                                     4. ◄──────────────── Online, pusht     │
│                                        KONFLIKT: Client rev 6 = Server 6   │
│                                        aber deviceId unterschiedlich!      │
│                                                                             │
│  KONFLIKT-AUFLÖSUNG:                                                       │
│  ══════════════════                                                        │
│                                                                             │
│  Option A: Last-Write-Wins (einfach, aber Datenverlust möglich)            │
│  Option B: User-Entscheidung (Dialog: "Lokal behalten" vs "Server nehmen") │
│  Option C: Merge (komplex, aber beste UX)                                  │
│                                                                             │
│  EMPFEHLUNG: Option B mit Option C für Hosts/Identities                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                    KONFLIKT ERKANNT                                 │   │
│  │                                                                     │   │
│  │  Ihr Vault wurde auf einem anderen Gerät geändert.                 │   │
│  │                                                                     │   │
│  │  Lokal: 5 Hosts, 3 Identities (vor 10 min geändert)               │   │
│  │  Server: 6 Hosts, 3 Identities (vor 5 min geändert)               │   │
│  │                                                                     │   │
│  │  [ Lokal behalten ]  [ Server nehmen ]  [ Zusammenführen ]        │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Merge-Strategie für Hosts/Identities

```
Merge-Regeln:
1. Hosts mit gleichem hostname+port werden verglichen
   - Neuere updatedAt gewinnt
   - Bei gleichem Zeitstempel: Server gewinnt

2. Identities mit gleichem Namen werden verglichen
   - Neuere updatedAt gewinnt

3. Neue Einträge (nur lokal oder nur Server) werden hinzugefügt

4. Gelöschte Einträge (deleted flag) werden synchronisiert
   - Löschung gewinnt nur wenn neuer als letzte Änderung
```

---

## Web-Interface

### Architektur

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                         WEB-INTERFACE ARCHITEKTUR                           │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  Browser (SPA - Single Page Application)                                   │
│  ══════════════════════════════════════                                    │
│                                                                             │
│  ┌─────────────────────────────────────────────────────────────────────┐   │
│  │                        React/Vue/Svelte App                         │   │
│  │                                                                     │   │
│  │  ┌───────────┐  ┌───────────┐  ┌───────────┐  ┌───────────┐       │   │
│  │  │   Login   │  │  Vault    │  │  Hosts    │  │  Settings │       │   │
│  │  │   2FA     │  │  Unlock   │  │  Browser  │  │  Profile  │       │   │
│  │  └───────────┘  └───────────┘  └───────────┘  └───────────┘       │   │
│  │                                                                     │   │
│  │  ┌─────────────────────────────────────────────────────────────┐   │   │
│  │  │                 Crypto Layer (Web Crypto API)               │   │   │
│  │  │                                                             │   │   │
│  │  │  • Argon2id (WASM)                                         │   │   │
│  │  │  • XChaCha20-Poly1305 (libsodium.js)                       │   │   │
│  │  │  • Key in sessionStorage (cleared on tab close)            │   │   │
│  │  └─────────────────────────────────────────────────────────────┘   │   │
│  └─────────────────────────────────────────────────────────────────────┘   │
│                                                                             │
│  SICHERHEIT:                                                               │
│  ══════════                                                                │
│  • Vault-Passwort NIEMALS an Server gesendet                              │
│  • Entschlüsselung vollständig im Browser                                 │
│  • Key nur in sessionStorage (nicht localStorage!)                        │
│  • CSP Header verhindern XSS-Angriffe                                     │
│  • KEINE Terminal-Funktionalität im Web (zu riskant)                      │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Web-Features (Read-Only + Management)

| Feature | Web | App | Begründung |
|---------|-----|-----|------------|
| Login/2FA | ✓ | ✓ | Account-Management |
| Vault anzeigen | ✓ | ✓ | Hosts/Keys einsehen |
| Hosts bearbeiten | ✓ | ✓ | Vault-Management |
| Identities verwalten | ✓ | ✓ | Key-Management |
| **SSH-Verbindung** | ✗ | ✓ | Sicherheitsrisiko |
| **Terminal** | ✗ | ✓ | Sicherheitsrisiko |
| Settings | ✓ | ✓ | Präferenzen |
| 2FA verwalten | ✓ | ✓ | Security-Settings |
| Geräte verwalten | ✓ | ✓ | Device-Management |

### Warum kein Web-Terminal?

```
SICHERHEITSBEDENKEN:
════════════════════

1. Private Keys im Browser
   - JavaScript kann Keys nicht sicher speichern
   - XSS-Angriffe könnten Keys stehlen
   - Browser-Extensions haben Zugriff

2. Session-Sicherheit
   - Web-Sessions sind anfälliger für Hijacking
   - Keine Hardware-Isolation

3. Keystroke-Logging
   - Malicious Scripts könnten Eingaben mitschneiden
   - Passphrasen für SSH-Keys gefährdet

4. Man-in-the-Middle
   - SSH-Verbindung müsste über Server laufen
   - Zero-Knowledge-Prinzip verletzt

EMPFEHLUNG: Web nur für Vault-Management, Terminal nur in nativer App
```

---

## API-Design

### Endpoints

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                            API ENDPOINTS                                    │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  AUTH                                                                       │
│  ════                                                                       │
│  POST   /api/v1/auth/register          # Neuen Account erstellen           │
│  POST   /api/v1/auth/login             # Login (returns JWT or TOTP req)   │
│  POST   /api/v1/auth/totp/validate     # TOTP-Code validieren              │
│  POST   /api/v1/auth/refresh           # Access Token erneuern             │
│  POST   /api/v1/auth/logout            # Session beenden                   │
│                                                                             │
│  2FA MANAGEMENT                                                             │
│  ══════════════                                                             │
│  GET    /api/v1/totp/setup             # QR-Code für TOTP erhalten         │
│  POST   /api/v1/totp/verify            # TOTP aktivieren (erster Code)     │
│  POST   /api/v1/totp/disable           # TOTP deaktivieren                 │
│  GET    /api/v1/recovery/codes         # Neue Recovery Codes generieren    │
│  POST   /api/v1/recovery/validate      # Mit Recovery Code einloggen       │
│                                                                             │
│  VAULT SYNC                                                                 │
│  ══════════                                                                 │
│  GET    /api/v1/vault                  # Vault-Blob abrufen                │
│  POST   /api/v1/vault                  # Vault-Blob hochladen              │
│  GET    /api/v1/vault/status           # Sync-Status (revision, etc.)      │
│  POST   /api/v1/vault/conflict/resolve # Konflikt auflösen                 │
│                                                                             │
│  DEVICES                                                                    │
│  ═══════                                                                    │
│  GET    /api/v1/devices                # Alle Geräte auflisten             │
│  POST   /api/v1/devices                # Neues Gerät registrieren          │
│  DELETE /api/v1/devices/:id            # Gerät entfernen (revoke access)   │
│  PATCH  /api/v1/devices/:id            # Gerät umbenennen                  │
│                                                                             │
│  USER                                                                       │
│  ════                                                                       │
│  GET    /api/v1/user/profile           # Profil abrufen                    │
│  PATCH  /api/v1/user/profile           # Profil ändern                     │
│  POST   /api/v1/user/password          # Account-Passwort ändern           │
│  DELETE /api/v1/user                   # Account löschen                   │
│                                                                             │
│  ADMIN (optional)                                                           │
│  ═════                                                                      │
│  GET    /api/v1/admin/users            # Alle User auflisten               │
│  PATCH  /api/v1/admin/users/:id        # User genehmigen/sperren           │
│  GET    /api/v1/admin/stats            # Server-Statistiken                │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

### Request/Response-Beispiele

```json
// POST /api/v1/vault
// Upload encrypted vault
{
  "vault_blob": "base64_encoded_encrypted_vault_file",
  "revision": 7,
  "device_id": "550e8400-e29b-41d4-a716-446655440000"
}

// Response
{
  "status": "ok",
  "revision": 7,
  "timestamp": 1705500000
}

// GET /api/v1/vault?since=6
// Response
{
  "vault_blob": "base64_encoded_encrypted_vault_file",
  "revision": 7,
  "updated_at": 1705500000,
  "updated_by_device": "550e8400-e29b-41d4-a716-446655440000"
}

// Conflict Response (409)
{
  "error": "conflict",
  "code": "VAULT_CONFLICT",
  "local_revision": 7,
  "server_revision": 7,
  "server_device_id": "different-device-uuid",
  "server_updated_at": 1705499000
}
```

---

## Datenbank-Schema

```sql
-- Users table
CREATE TABLE users (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    email VARCHAR(255) UNIQUE NOT NULL,
    password_hash VARCHAR(255) NOT NULL,

    -- Account status
    is_approved BOOLEAN DEFAULT false,
    is_admin BOOLEAN DEFAULT false,
    is_blocked BOOLEAN DEFAULT false,

    -- TOTP 2FA
    totp_secret BYTEA,
    totp_enabled BOOLEAN DEFAULT false,
    totp_verified_at TIMESTAMP,

    -- Timestamps
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),
    last_login_at TIMESTAMP
);

-- Devices (registered app instances)
CREATE TABLE devices (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    device_name VARCHAR(255) NOT NULL,
    device_type VARCHAR(50) NOT NULL,  -- 'windows', 'linux', 'android', 'web'
    device_model VARCHAR(255),
    app_version VARCHAR(50),

    last_sync_at TIMESTAMP,
    created_at TIMESTAMP DEFAULT NOW(),
    updated_at TIMESTAMP DEFAULT NOW(),

    UNIQUE(user_id, device_name)
);

-- Encrypted vaults (ONE per user, zero-knowledge)
CREATE TABLE encrypted_vaults (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID UNIQUE NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    -- The encrypted vault file (already encrypted by client)
    vault_blob BYTEA NOT NULL,

    -- Vault metadata (from header, not sensitive)
    revision INTEGER NOT NULL DEFAULT 1,
    vault_version INTEGER DEFAULT 1,  -- VBT1 format version

    -- Sync tracking
    updated_by_device UUID REFERENCES devices(id),
    updated_at TIMESTAMP DEFAULT NOW(),
    created_at TIMESTAMP DEFAULT NOW()
);

-- Sync log for audit trail
CREATE TABLE sync_logs (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID REFERENCES devices(id),

    action VARCHAR(50) NOT NULL,  -- 'push', 'pull', 'conflict'
    revision_before INTEGER,
    revision_after INTEGER,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Recovery codes for 2FA
CREATE TABLE recovery_codes (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,

    code_hash VARCHAR(255) NOT NULL,
    used BOOLEAN DEFAULT false,
    used_at TIMESTAMP,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Refresh tokens for JWT
CREATE TABLE refresh_tokens (
    id UUID PRIMARY KEY DEFAULT gen_random_uuid(),
    user_id UUID NOT NULL REFERENCES users(id) ON DELETE CASCADE,
    device_id UUID NOT NULL REFERENCES devices(id) ON DELETE CASCADE,

    token_hash VARCHAR(255) NOT NULL,
    expires_at TIMESTAMP NOT NULL,
    revoked BOOLEAN DEFAULT false,

    created_at TIMESTAMP DEFAULT NOW()
);

-- Indexes
CREATE INDEX idx_devices_user_id ON devices(user_id);
CREATE INDEX idx_sync_logs_user_id ON sync_logs(user_id);
CREATE INDEX idx_refresh_tokens_user_id ON refresh_tokens(user_id);
CREATE INDEX idx_refresh_tokens_expires ON refresh_tokens(expires_at);
```

---

## Sicherheitsmaßnahmen

### Checkliste

```
┌─────────────────────────────────────────────────────────────────────────────┐
│                      SECURITY CHECKLIST                                     │
├─────────────────────────────────────────────────────────────────────────────┤
│                                                                             │
│  TRANSPORT                                                                  │
│  ═════════                                                                  │
│  [x] TLS 1.3 only                                                          │
│  [x] HSTS mit includeSubDomains                                            │
│  [x] Certificate Pinning (optional, für App)                               │
│                                                                             │
│  AUTHENTICATION                                                             │
│  ══════════════                                                             │
│  [x] bcrypt für Account-Passwort (cost 12)                                 │
│  [x] TOTP 2FA mit RFC 6238                                                 │
│  [x] Rate Limiting für Login (5/min)                                       │
│  [x] Account Lockout nach 10 Fehlversuchen                                 │
│  [x] Recovery Codes (8 Stück, einmalig)                                    │
│                                                                             │
│  SESSION                                                                    │
│  ═══════                                                                    │
│  [x] JWT mit kurzer Lebensdauer (15 min)                                   │
│  [x] Refresh Tokens (30 Tage, revokierbar)                                 │
│  [x] Device-Binding für Tokens                                             │
│  [x] HttpOnly, Secure, SameSite=Strict Cookies                             │
│                                                                             │
│  API                                                                        │
│  ═══                                                                        │
│  [x] Input Validation (alle Endpoints)                                     │
│  [x] Prepared Statements (SQL Injection)                                   │
│  [x] Rate Limiting pro Endpoint                                            │
│  [x] CORS korrekt konfiguriert                                             │
│  [x] Request Size Limits (Vault max 10MB)                                  │
│                                                                             │
│  HEADERS                                                                    │
│  ═══════                                                                    │
│  [x] Content-Security-Policy                                               │
│  [x] X-Content-Type-Options: nosniff                                       │
│  [x] X-Frame-Options: DENY                                                 │
│  [x] Referrer-Policy: strict-origin-when-cross-origin                      │
│                                                                             │
│  ZERO-KNOWLEDGE                                                             │
│  ══════════════                                                             │
│  [x] Vault bereits client-seitig verschlüsselt                             │
│  [x] Server speichert nur Blob                                             │
│  [x] Keine Vault-Passwort-Übertragung                                      │
│  [x] Keine serverseitige Entschlüsselung möglich                           │
│                                                                             │
└─────────────────────────────────────────────────────────────────────────────┘
```

---

## Technologie-Stack

### Server

| Komponente | Technologie | Begründung |
|------------|-------------|------------|
| **Sprache** | Go | Performance, einfaches Deployment, VibedTracker-Erfahrung |
| **Framework** | Gin | Bewährt, schnell, Middleware-Support |
| **Datenbank** | PostgreSQL | Zuverlässig, UUID-Support, JSON-Support |
| **Reverse Proxy** | Caddy | Auto-HTTPS, einfache Config |
| **Container** | Docker | Portabilität, einfaches Deployment |

### Web-Interface

| Komponente | Technologie | Begründung |
|------------|-------------|------------|
| **Framework** | Svelte/SvelteKit | Klein, schnell, einfach |
| **Crypto** | libsodium.js | XChaCha20-Poly1305 Unterstützung |
| **Argon2** | argon2-browser (WASM) | Client-seitige KDF |
| **Build** | Vite | Schnell, modern |

### App-Integration (core_sync Package)

```dart
// Neues Package: packages/core_sync

abstract class SyncService {
  Future<void> login(String email, String password);
  Future<void> validateTotp(String code);
  Future<void> logout();

  Future<SyncStatus> getStatus();
  Future<VaultData?> pullVault();
  Future<void> pushVault(VaultData vault);

  Future<List<Device>> getDevices();
  Future<void> removeDevice(String deviceId);

  Stream<SyncEvent> get syncEvents;
}

enum SyncStatus {
  notLoggedIn,
  upToDate,
  pendingPush,
  pendingPull,
  conflict,
}
```

---

## Implementierungs-Phasen

### Phase 1: Core Server (2-3 Wochen)

```
[x] Projekt-Setup (Go, Gin, PostgreSQL)
[x] User-Registration & Login
[x] JWT Token-Management
[x] TOTP 2FA Implementierung
[x] Device-Management
[ ] Vault Push/Pull Endpoints
[ ] Konflikt-Erkennung
[ ] Basic Admin-Interface
```

### Phase 2: App-Integration (2 Wochen)

```
[ ] core_sync Package erstellen
[ ] Login/2FA UI in App
[ ] Sync-Status Anzeige
[ ] Push/Pull Implementierung
[ ] Konflikt-Dialog
[ ] Offline-Support
```

### Phase 3: Web-Interface (2 Wochen)

```
[ ] SvelteKit Projekt-Setup
[ ] Login/2FA Seiten
[ ] Vault-Anzeige (read-only zunächst)
[ ] Crypto-Integration (Argon2, XChaCha20)
[ ] Hosts/Identities Browser
[ ] Device-Management UI
```

### Phase 4: Erweiterungen (ongoing)

```
[ ] WebAuthn/Passkey Support
[ ] Vault-Bearbeitung im Web
[ ] Push-Notifications für Sync
[ ] Audit-Logs
[ ] Self-Hosting Dokumentation
```

---

## Offene Fragen

1. **Self-Hosted vs. Managed Service?**
   - Self-Hosted: User hosten eigenen Server
   - Managed: Wir betreiben Server (DSGVO, Kosten)
   - Hybrid: Beides anbieten

2. **Account-Approval-Workflow?**
   - Offen für alle (Spam-Risiko)
   - Admin-Approval (wie VibedTracker)
   - Invite-Only

3. **Pricing-Modell (falls Managed)?**
   - Free Tier (1 Device, 100 Hosts)
   - Pro (unlimited, €X/Monat)
   - Self-Hosted (kostenlos)

4. **Vault-Versionierung?**
   - Nur letzte Version speichern
   - History der letzten N Versionen
   - Unbegrenzte History (Storage-Kosten)

---

*Erstellt: Januar 2025*
*Status: Planungsphase*
