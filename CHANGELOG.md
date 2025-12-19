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

### SSH Authentication Improvements

- **Password authentication**: Always prompt for password before connecting; leave empty to use key-only auth.
- **Auth method logging**: Debug output shows available auth methods (`key=true/false, password=true/false`).
- **Key parsing error handling**: If private key parsing fails, continues with password auth as fallback.
- **Better error messages**: Logs show number of keys loaded and parsing errors.

### Vault Auto-Unlock

- **Auto-unlock on startup**: If vault password was saved securely ("Remember securely"), vault unlocks automatically on app start.
- **Last vault persistence**: Remembers last opened vault path across sessions.

### UX Improvements

- **Enter key confirms dialogs**: Password dialogs (vault and SSH) can be confirmed with Enter key.
- **Autofocus on password fields**: Password input fields receive focus automatically.

### Windows Platform Fixes

- **Fixed xterm focus errors**: Disabled autofocus on `VibedTerminalView` to prevent Windows `PlatformException: view ID is null`.
- **Delayed focus request**: Added 100ms delay before requesting terminal focus after tab creation.
- **Fixed controller disposal errors**: Removed premature `TextEditingController.dispose()` calls that caused "used after disposed" errors during dialog animations.
- **Fixed FocusNode disposal errors**: Removed manual FocusNode management in favor of Flutter's built-in autofocus.

### Code Structure

- Extracted screens from monolithic `main.dart` into `lib/screens/` directory:
  - `vault_screen.dart` - Vault creation/unlock UI
  - `hosts_screen.dart` - Host and identity management
  - `terminal_screen.dart` - Terminus-like multi-tab terminal
- Replaced `findAncestorStateOfType` hack with clean `onConnectHost` callback pattern.
- Added `clearPendingConnect()` to VaultService for proper cleanup.

### Known Issues

- **Windows PlatformException**: `Could not set client, view ID is null` errors still appear in debug console but don't block functionality. This is a known xterm/Flutter Windows issue.
- **Key auth may fail**: If the private key in the vault doesn't match the public key authorized on the server, key auth fails. Use password auth or import the correct key.

### Previous Changes

- Terminal tab can load saved vault hosts to prefill connection details.
- SSH connections now prompt for host-key verification and remember trusted fingerprints in the vault metadata.
- Vault service exposes helpers to read/write trusted host keys; vault payload updates bump revision/updatedAt.
- SSH core supports host-key verification callbacks with formatted fingerprints for UI prompts.
- Terminal tab offers an experimental interactive shell powered by xterm, with host-selected connections and quick commands.
- Connection form supports supplying a private-key passphrase.
