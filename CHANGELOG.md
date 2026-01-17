# Changelog

All notable changes to VibedTerm will be documented in this file.

## [0.2.0] - 2026-01-17

### Added

#### tmux Integration
- **Auto-attach**: Automatically attach to or create tmux sessions on SSH connect
- **Session picker dialog**: Choose from existing sessions when multiple are available
- **Session manager UI**: Create, attach, detach, and kill tmux sessions via grid icon in status bar
- **Tab labels**: Display attached tmux session name in tab header (e.g., "myserver [dev]")
- **Per-host configuration**: Enable tmux auto-attach and set session name per host

#### Terminal Theming
- **12 color themes**: Default, Solarized Dark/Light, Monokai, Dracula, Nord, Gruvbox Dark/Light, One Dark/Light, GitHub Light, Tomorrow Light
- **App-wide theming**: Terminal theme colors apply to entire application UI
- **Theme converter**: `TerminalThemeConverter` generates Flutter `ThemeData` from terminal themes

#### Settings Dialog
- **Appearance tab**: Color theme, font size, font family, background opacity, cursor style
- **SSH tab**: Keepalive interval, connection timeout, default port, auto-reconnect toggle
- **Accessible via sidebar**: Click gear icon to open settings

#### UI Redesign
- **Vertical sidebar**: Compact 56px sidebar with navigation icons at top
- **Rotated branding**: "VibedTerm" text displayed vertically above settings icon
- **No top AppBar**: More screen space for terminal content
- **Custom app icon**: Terminal-style icon with cyan prompt on dark background

#### SSH Settings Model
- `sshKeepaliveInterval`: Seconds between keepalive packets (0 = disabled)
- `sshConnectionTimeout`: Connection timeout in seconds
- `sshDefaultPort`: Default SSH port for new hosts
- `sshAutoReconnect`: Auto-reconnect on connection loss (UI only, implementation planned)

### Changed
- Moved from horizontal AppBar to vertical sidebar navigation
- Settings now accessible from dedicated settings icon instead of Vault screen
- Platform directories (android, windows, linux) now tracked in git

### Fixed
- Window title now shows "VibedTerm" on all platforms
- App icon properly displayed on Windows and Android

---

## [0.1.0] - 2024-12

### Added

#### Terminal UX (Terminus-like)
- **Multi-connection tabs**: Each tab owns its own `SshConnectionManager` - connect to multiple hosts simultaneously
- **Tab bar with status indicators**: Colored dots show connection state (green=connected, amber=connecting, red=error, grey=disconnected)
- **Quick-connect flow**: [+] button opens BottomSheet host picker; empty state shows ActionChip shortcuts
- **Collapsible logs drawer**: Per-tab logs accessible via status bar toggle
- **Close confirmation**: Dialog prompts before closing tabs with active connections
- **Trusted keys dialog**: Host key management via menu

#### SSH Authentication
- **Password authentication**: Dialog prompt for password before connecting
- **Key authentication**: Link identities (private keys) to hosts
- **Auth method logging**: Debug output shows available auth methods
- **Key parsing error handling**: Falls back to password auth if key parsing fails

#### Vault System
- **Encrypted vault**: Argon2id KDF with XChaCha20-Poly1305 or AES-256-GCM encryption
- **Auto-unlock**: Remember vault password securely for auto-unlock on startup
- **Host key persistence**: Trusted SSH host keys stored in vault metadata

#### UX Improvements
- **Enter key confirms dialogs**: Password dialogs can be confirmed with Enter
- **Autofocus on password fields**: Automatic focus for faster input

### Fixed

#### Windows Platform
- Disabled autofocus on `VibedTerminalView` to prevent `PlatformException`
- Added delay before requesting terminal focus after tab creation
- Fixed `TextEditingController` disposal errors during dialog animations
- Fixed `FocusNode` disposal errors

### Code Structure
- Extracted screens into `lib/screens/` directory
- Clean callback patterns replacing `findAncestorStateOfType` hacks
- Monorepo structure with Melos orchestration

---

## Package Versions

| Package | Version |
|---------|---------|
| ssh_client_app | 0.1.0 |
| core_vault | 0.1.0 |
| core_ssh | 0.1.0 |
| core_sync | 0.1.0 |
| ui_terminal | 0.1.0 |
