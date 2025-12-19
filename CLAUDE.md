# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project Overview

VibedTerm is a Flutter-based SSH client targeting Windows, Linux, and Android. It features an encrypted vault for storing SSH credentials and optional file-based sync via user-chosen cloud folders (OneDrive/Google Drive).

## Build and Development Commands

```bash
# Analyze entire monorepo
flutter analyze

# Run tests for specific packages
flutter test packages/core_vault
flutter test packages/core_ssh

# Run the app (from apps/ssh_client_app or use -d to specify device)
cd apps/ssh_client_app && flutter run -d <device>

# Melos commands (monorepo orchestration)
melos run analyze          # Analyze all packages
melos run check            # Analyze + run core package tests
melos run test             # Run all tests
melos run format           # Format all packages
```

## Architecture

### Monorepo Structure (Melos-managed)

- **apps/ssh_client_app** - Main Flutter application entry point
- **packages/core_vault** - Encrypted vault format, cryptography, and data models (pure Dart, no Flutter)
- **packages/core_ssh** - SSH session management wrapping dartssh2 (pure Dart)
- **packages/core_sync** - Sync abstraction for file-based cloud sync (planned)
- **packages/ui_terminal** - Terminal widget integration using xterm package

### Key Architectural Patterns

**Vault System (core_vault)**
- Binary vault format with header containing KDF params (Argon2id), cipher (XChaCha20-Poly1305 or AES-256-GCM), nonce, and payload length
- `VaultFile` class handles create/open/save with atomic writes (temp file + rename)
- Data models: `VaultHost`, `VaultIdentity`, `VaultSnippet`, `VaultSettings`
- Trusted host keys stored in `VaultData.meta['trustedHostKeys']`

**SSH Layer (core_ssh)**
- `SshConnectionManager` wraps dartssh2 with higher-level status events and logging
- `SshClientAdapter` interface abstracts the underlying SSH client for testability
- `SshTarget` configures connection with host key verification callback
- `SshShellSession` provides streams (stdout/stderr) and write/resize/close methods

**Terminal Integration (ui_terminal)**
- `TerminalBridge` connects SSH streams to xterm `Terminal` instance
- `VibedTerminalView` widget wraps xterm's `TerminalView`

**App Structure (ssh_client_app)**
- `lib/main.dart` - App shell, navigation, and `HomeShell` widget
- `lib/screens/` - Separated screen widgets:
  - `vault_screen.dart` - Vault creation/unlock UI
  - `hosts_screen.dart` - Host and identity management
  - `terminal_screen.dart` - Terminus-like multi-tab SSH terminal
- `lib/services/vault_service.dart` - Orchestrates vault operations via `ValueNotifier<VaultState>`

**Terminal Architecture (Terminus-like)**
- Each tab (`_ConnectionTab`) owns its own `SshConnectionManager` - independent connections
- `_ConnectionTab` contains: manager, host, identity, bridge, session, status, logs
- UI: Tab-Bar with status dots, expanded terminal area, compact status bar, collapsible logs drawer
- Quick-connect via BottomSheet host picker or ActionChips in empty state
- Tab close with confirmation dialog for active connections

### Data Flow

1. User creates/unlocks vault via `VaultService` (password-derived key with Argon2id)
2. Hosts and identities stored in `VaultData`, encrypted on disk
3. User selects host → new `_ConnectionTab` created with its own `SshConnectionManager`
4. Tab connects to host, auto-opens shell, attaches to `TerminalBridge`
5. Terminal output flows: SSH stdout/stderr -> TerminalBridge -> xterm Terminal
6. User input flows: xterm onOutput -> TerminalBridge.onOutput -> SSH stdin
7. Closing tab disconnects that connection (independent of other tabs)

### Dependencies

- **cryptography** - KDF and AEAD encryption in core_vault
- **dartssh2** - SSH2 protocol implementation in core_ssh
- **xterm** - Terminal emulation widget in ui_terminal
- **flutter_secure_storage** - Device keychain for remembered passwords
- **shared_preferences** - Last vault path persistence
