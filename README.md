# VibedTerm

Flutter-based SSH client targeting Windows, Linux, and Android with an encrypted vault and optional file-based sync via user-chosen OneDrive/Google Drive folders.

## Features

- **Encrypted Vault**: Store SSH hosts and identities securely with Argon2id KDF and XChaCha20-Poly1305/AES-256-GCM encryption.
- **Multi-Tab Terminal**: Terminus-like UX with independent SSH connections per tab.
- **Quick Connect**: Fast host selection via BottomSheet picker or ActionChip shortcuts.
- **Host Key Verification**: Trust prompts with fingerprint display, persisted in vault.

## Docs

- Project plan: `docs/plan.md`
- Changelog: `CHANGELOG.md`
- Claude Code guidance: `CLAUDE.md`

## Repo Layout

- `apps/ssh_client_app` — Flutter app entry point
- `packages/core_vault` — Vault format, crypto, data models (pure Dart)
- `packages/core_ssh` — SSH session management wrapping dartssh2 (pure Dart)
- `packages/core_sync` — Sync abstraction for file-based cloud sync (planned)
- `packages/ui_terminal` — Terminal widget integration using xterm

Melos configuration is provided (`melos.yaml`) for monorepo orchestration.

## Running

From repo root:

```bash
flutter analyze
flutter test packages/core_vault
flutter test packages/core_ssh
```

App: `cd apps/ssh_client_app && flutter run -d <device>`

Melos helpers:

```bash
melos run analyze
melos run check    # analyze + core package tests
```

## Current UI

### Vault Tab
Create or unlock encrypted vault files. Supports password memory (session or secure storage).

### Hosts Tab
Manage SSH hosts and identities stored in the vault. Link identities (private keys) to hosts.

### Terminal Tab
- **Tab Bar**: Shows open connections with status indicators (colored dots).
- **Quick Connect**: Click [+] for host picker or use ActionChips in empty state.
- **Terminal View**: Full xterm-based terminal with resize support.
- **Status Bar**: Connection info, special key buttons (Esc, Ctrl+C/D, Tab), paste, logs toggle.
- **Per-Tab Logs**: Collapsible drawer showing connection logs for active tab.

Each tab maintains its own independent SSH connection - you can connect to multiple different servers simultaneously.
