# Changelog

## Unreleased

### Terminal UX Overhaul (Terminus-like)

- **Multi-connection tabs**: Each tab now owns its own `SshConnectionManager` - connect to multiple different hosts simultaneously with independent connections.
- **Simplified UI**: Removed connection card, command card, and advanced form. Terminal view now takes center stage.
- **Tab bar with status indicators**: Colored dots show connection state (green=connected, amber=connecting, red=error, grey=disconnected).
- **Quick-connect flow**: [+] button opens BottomSheet host picker; empty state shows ActionChip shortcuts for fast connection.
- **Collapsible logs drawer**: Per-tab logs accessible via status bar toggle or menu.
- **Close confirmation**: Dialog prompts before closing tabs with active connections.
- **Trusted keys dialog**: Host key management moved to menu dialog.

### Code Structure

- Extracted screens from monolithic `main.dart` into `lib/screens/` directory:
  - `vault_screen.dart` - Vault creation/unlock UI
  - `hosts_screen.dart` - Host and identity management
  - `terminal_screen.dart` - Terminus-like multi-tab terminal
- Replaced `findAncestorStateOfType` hack with clean `onConnectHost` callback pattern.
- Added `clearPendingConnect()` to VaultService for proper cleanup.

### Previous Changes

- Terminal tab can load saved vault hosts to prefill connection details.
- SSH connections now prompt for host-key verification and remember trusted fingerprints in the vault metadata.
- Vault service exposes helpers to read/write trusted host keys; vault payload updates bump revision/updatedAt.
- SSH core supports host-key verification callbacks with formatted fingerprints for UI prompts.
- Terminal tab offers an experimental interactive shell powered by xterm, with host-selected connections and quick commands.
- Connection form supports supplying a private-key passphrase.
