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
melos bootstrap            # Initial setup after clone
melos run analyze          # Analyze all packages
melos run check            # Analyze + run core package tests
melos run test             # Run all tests
melos run format           # Format all packages
```

## CI/CD

GitHub Actions workflow (`.github/workflows/ci.yaml`) runs on push to main and all PRs:
- Flutter setup (stable channel)
- `melos bootstrap`
- `melos run check` (analyze + core_vault & core_ssh tests)

## Architecture

### Monorepo Structure (Melos-managed)

- **apps/ssh_client_app** - Main Flutter application entry point
- **packages/core_vault** - Encrypted vault format, cryptography, and data models (pure Dart, no Flutter)
- **packages/core_ssh** - SSH session management wrapping dartssh2 (pure Dart)
- **packages/core_sync** - Sync abstraction for file-based cloud sync (planned)
- **packages/ui_terminal** - Terminal widget (xterm.js via WebView on Win/Android/iOS, native xterm Dart on Linux)

### Key Architectural Patterns

**Vault System (core_vault)**
- Binary vault format with header containing KDF params (Argon2id), cipher (XChaCha20-Poly1305 or AES-256-GCM), nonce, and payload length
- `VaultFile` class handles create/open/save with atomic writes (temp file + rename)
- Data models: `VaultHost`, `VaultIdentity`, `VaultSnippet`, `VaultSettings`
- `VaultHost` includes tmux settings: `tmuxAutoAttach`, `tmuxSessionName`
- `VaultSettings` includes appearance (theme, font) and SSH settings (keepalive, timeout, default port, auto-reconnect)
- Trusted host keys stored in `VaultData.meta['trustedHostKeys']`

**SSH Layer (core_ssh)**
- `SshConnectionManager` wraps dartssh2 with higher-level status events and logging
- `SshClientAdapter` interface abstracts the underlying SSH client for testability
- `SshTarget` configures connection with host key verification callback
- `SshShellSession` provides streams (stdout/stderr) and write/resize/close methods
- Key parsing with error handling: logs failures, continues with password auth

**Terminal Integration (ui_terminal)**
- Dual-backend architecture: xterm.js via WebView (Windows, Android, iOS, macOS) / native xterm Dart (Linux)
- `TerminalBridge` abstracts the backend — communicates via JS channels (WebView) or directly (native)
- `VibedTerminalView` is a platform-adaptive factory widget selecting the correct backend
- `VibedTerminalTheme` (own type, typedef'd as `TerminalTheme`) with `toXtermJsTheme()` serialization
- `TerminalThemePresets` provides 12 color themes, `TerminalThemeConverter` generates Flutter ThemeData
- WebView loads bundled xterm.js v6 + FitAddon from package assets (no CDN dependency)
- Bridge features: `ready` future, `viewWidth`/`viewHeight`, `onResize` callback, pending write buffer
- Data flow (WebView): SSH stdout → Dart → JS Channel → xterm.js | xterm.js input → JS Channel → Dart → SSH stdin
- Data flow (Linux): SSH stdout → Dart → xterm Terminal.write() | Terminal.onOutput → Dart → SSH stdin

**App Structure (ssh_client_app)**
- `lib/main.dart` - App shell with vertical sidebar, settings dialog, and `HomeShell` widget
- `lib/screens/` - Separated screen widgets:
  - `vault_screen.dart` - Vault creation/unlock UI
  - `hosts_screen.dart` - Host and identity management
  - `terminal_screen.dart` - Terminus-like multi-tab SSH terminal with tmux integration
- `lib/services/vault_service.dart` - Orchestrates vault operations via `ValueNotifier<VaultState>`

**UI Architecture**
- Vertical sidebar (56px) with navigation icons at top, rotated "VibedTerm" branding above settings gear at bottom
- No top AppBar - maximizes terminal screen space
- Settings dialog with Appearance (themes, fonts) and SSH (keepalive, timeout) tabs
- App-wide theming: `TerminalThemeConverter` generates Flutter `ThemeData` from terminal theme colors

**tmux Integration**
- `VaultHost` has `tmuxAutoAttach` and `tmuxSessionName` fields for per-host configuration
- On connect, if tmux enabled: runs `tmux list-sessions` via `SshConnectionManager.runCommand()`
- `TmuxSession.parseListSessions()` parses tmux output format
- Session picker dialog shown when multiple sessions exist
- `_ConnectionTab.attachedTmuxSession` tracks current session, shown in tab header
- Session manager UI accessible via grid icon in status bar

**Terminal Architecture (Terminus-like)**
- Each tab (`_ConnectionTab`) owns its own `SshConnectionManager` - independent connections
- `_ConnectionTab` contains: manager, host, identity, password, bridge, session, status, logs
- UI: Tab-Bar with status dots, expanded terminal area, compact status bar, collapsible logs drawer
- Quick-connect via BottomSheet host picker or ActionChips in empty state
- Tab close with confirmation dialog for active connections

### Data Flow

1. User creates/unlocks vault via `VaultService` (password-derived key with Argon2id)
2. Hosts and identities stored in `VaultData`, encrypted on disk
3. User selects host → password dialog shown → new `_ConnectionTab` created
4. Tab connects with key auth (if identity linked) and/or password auth
5. Tab auto-opens shell after `await bridge.ready`, attaches to `TerminalBridge`
6. Terminal output flows: SSH stdout/stderr -> TerminalBridge -> JS Channel -> xterm.js (or native Terminal)
7. User input flows: xterm.js onData -> JS Channel -> TerminalBridge.onOutput -> SSH stdin
8. Closing tab disconnects that connection (independent of other tabs)

### Dependencies

- **cryptography** - KDF and AEAD encryption in core_vault
- **dartssh2** - SSH2 protocol implementation in core_ssh
- **xterm** - Terminal emulation (native Dart, Linux fallback) in ui_terminal
- **xterm.js** - Terminal emulation (bundled JS, via WebView) in ui_terminal
- **flutter_inappwebview** - WebView for xterm.js on Windows, Android, iOS, macOS
- **flutter_secure_storage** - Device keychain for remembered passwords
- **shared_preferences** - Last vault path persistence

## Troubleshooting

### SSH Authentication Issues

**Symptoms:** "All authentication methods failed" despite having a key configured.

**Debug output to check:**
```
[SSH-DEBUG] User: username
[SSH-DEBUG] Host: hostname:port
[SSH-DEBUG] Key: -----BEGIN OPENSSH... (first 50 chars)
[SSH-DEBUG] Password provided: true/false
[SSH:Host] Loaded N key(s) from private key
[SSH:Host] Auth methods: key=true/false, password=true/false
```

**Common causes:**
1. **Wrong key in vault**: The private key stored in the vault is different from the one authorized on the server. Verify with `ssh -vv user@host` to see which key works.
2. **Key not authorized on server**: Public key not in `~/.ssh/authorized_keys` on the remote host.
3. **Key parsing failed**: Check for "Failed to parse private key" in logs.
4. **No password provided**: If key auth fails and password is empty, connection fails.

**Solution:** Import the correct key (from `~/.ssh/id_*`) into the vault identity.

### Windows/Android Platform Issues (RESOLVED)

**Previous issues** with the Dart xterm package (PlatformExceptions, FocusNode disposal errors)
have been resolved by migrating to xterm.js via WebView on non-Linux platforms. The WebView
handles its own text input and focus management, bypassing Flutter's TextInputClient entirely.

The native Dart xterm fallback is retained for Linux only, where these issues do not occur.

## Code Conventions

- Screens in `lib/screens/` with barrel export via `screens.dart`
- Services in `lib/services/` using `ValueNotifier` for state
- Each `_ConnectionTab` is self-contained with its own SSH connection lifecycle
- Use `// ignore: avoid_print` for intentional debug prints
- Password dialogs use `autofocus: true` and `onSubmitted` for Enter key support
- All data models in core_vault are marked `@immutable`

## Key Files

When navigating this codebase, these are the most important files:

- `melos.yaml` - Monorepo configuration and scripts
- `packages/core_vault/lib/core_vault.dart` - Vault implementation with all data models
- `packages/core_ssh/lib/core_ssh.dart` - SSH connection manager with tmux support
- `packages/ui_terminal/lib/ui_terminal.dart` - Barrel exports and platform-adaptive VibedTerminalView
- `packages/ui_terminal/lib/src/terminal_bridge.dart` - Dual-mode bridge (WebView JS channels / native xterm)
- `packages/ui_terminal/lib/src/webview_terminal_view.dart` - xterm.js WebView widget
- `packages/ui_terminal/assets/terminal.html` - xterm.js HTML shell with JS channel protocol
- `apps/ssh_client_app/lib/main.dart` - App shell, sidebar, settings dialog
- `apps/ssh_client_app/lib/screens/terminal_screen.dart` - Multi-tab terminal with tmux integration
- `apps/ssh_client_app/lib/services/vault_service.dart` - State orchestration
