# VibedTerm — Development Plan

Actionable roadmap for a Flutter SSH client targeting Windows, Linux, and Android with a file-based encrypted vault and optional cloud sync.

## Product Goal

- SSH terminal with tabs/sessions
- Hosts/profiles management
- Keys/secrets stored in an encrypted vault
- Sync via user-chosen OneDrive/Google Drive folder (native APIs later)
- Stable, secure, maintainable UX with Android keyboard friendliness

## Key Strategy (keeps the project simple)

**Sync as “vault file in a sync folder” first.**
- User picks a path such as `OneDrive/.../ssh_vault.vlt` or a Drive folder.
- OneDrive/Drive clients handle transport; the app reads/writes one vault file.
- Native Graph/Drive APIs + conflict resolution come later (Stage 6+).

## Repository Layout (monorepo)

```
/apps/ssh_client_app          # Flutter UI
/packages/core_vault          # Vault format, crypto, data models
/packages/core_sync           # Sync abstraction (file-based first)
/packages/core_ssh            # SSH session management (dartssh2 wrapper)
/packages/ui_terminal         # Terminal widget wrapper (xterm)
```

## Stages

### Stage 0 — Project foundation
- Deliverables: Flutter app with desktop targets enabled; `analysis_options.yaml` and linting; minimal navigation/theme; dummy screens (Vault Unlock / Host List / Terminal); optional CI (flutter analyze/test).
- Acceptance: `flutter run` works on Windows/Linux/Android; basic navigation/state works.

### Stage 1 — Vault v1: data model + encryption (critical)
- Vault format: header (magic, version, KDF params, salt, nonce); payload JSON/CBOR (hosts, keys, snippets, settings).
- Crypto: AES-256-GCM or XChaCha20-Poly1305; KDF: Argon2id (scrypt fallback if needed).
- Deliverables: `core_vault` with `VaultFile.create/open/save`, CRUD for hosts/identities/snippets/settings, roundtrip tests.
- Acceptance: wrong password → defined error; file not human-readable; versioning ready.

### Stage 2 — Secrets handling: OS keystore optional
- Goal: “Remember on this device” by storing wrapped vault key in secure storage.
- Platforms: Android/Windows/Linux via `flutter_secure_storage` where available; fallback to password-only.
- Acceptance: without remember → password always required; with remember → unlock via device keystore.

### Stage 3 — Hosts UI + key import (usable product)
- Screens: vault select/create, host list (filter/tags/search), host editor (host/port/user/auth, optional jump host), key import (paste/file, optional passphrase).
- Acceptance: host persists after app restart; imported key stored in vault.

### Stage 4 — SSH core + terminal MVP
- `core_ssh`: `SshConnectionManager`, keepalive, error mapping.
- `ui_terminal`: terminal widget (xterm), copy/paste, Android extra key row (Esc/Ctrl/Tab/Arrows), resize handling.
- Acceptance: SSH connect to VPS works; terminal I/O stable; clean disconnect.

### Stage 5 — Multi-session (tabs)
- Tabs UI, session list, reconnect button; optional quick-connect palette (Ctrl+K).
- Acceptance: two hosts open in parallel; tab switching stable; basic leak check.

### Stage 6 — File-based sync v1
- Mechanics: file watcher on desktop, polling fallback on Android; vault metadata includes `lastModified` + `revision`; prompt on remote change.
- Settings: vault path picker; sync mode manual/auto; sync status indicator.
- Acceptance: change on Windows → after sync Android can reload and see it; conflicts detected if both change.

### Stage 7 — Conflict resolution (merge)
- Vault contains `revision`, `deviceId`, optional `changeLog` metadata.
- `VaultMergeEngine` and conflict UI (merge per field for hosts/snippets, choose/duplicate for keys).
- Acceptance: simulated conflict can be merged without data loss.

### Stage 8 — SFTP v1
- SFTP browser per session; upload/download; basic permissions handling.
- Acceptance: upload to `/tmp`, download back.

### Stage 9 — Advanced networking
- Jump host/bastion chain (≥1 hop); port forwarding (local, optional dynamic/SOCKS).
- Acceptance: connection via bastion works; local forward to internal service works.

### Stage 10 — Native cloud sync (optional “hard mode”)
- OAuth flows; providers for OneDrive (Graph) and Google Drive; lock/lease best effort; optional delta sync.
- Acceptance: login → vault list → download/upload; conflicts handled cleanly.

## Definition of Done per stage

- Unit tests (at minimum `core_vault`, merge logic when present)
- README update (how to run + stage notes)
- Demo script (e.g., `scripts/demo_stage_4.md`)

## Workflow (for Codex-sized tasks)

- Work in small, PR-like chunks per stage.
- Example prompts: “Implement `core_vault` with AES-GCM encryption, header, Argon2id KDF, and roundtrip tests.”; “Add Vault CRUD for Hosts + Identities with validation and migration scaffold v1→v2.”; “Implement `SshConnectionManager` using dartssh2 and integrate xterm with Android extra keys row.”

## Key Risks (watch early)

- Android terminal UX (keyboard/IME/Ctrl/Alt); test early (Stage 4).
- Linux keystore availability varies; keep a password-only fallback.
- Vault crypto: prioritize correctness over cleverness.
- Native cloud sync only after file-based flow (avoid early OAuth complexity).
