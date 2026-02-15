# TODO & Roadmap

## Recently Completed

- [x] Host groups/folders: Organize hosts in collapsible folder sections
- [x] Tailscale node discovery: Scan and import Tailscale peers as hosts
- [x] SFTP file browser with directory navigation, upload/download, delete, new folder
- [x] Drag & drop file upload on SFTP browser and terminal (desktop_drop)
- [x] Quick-connect bar: Type `user@host:port` directly in tab bar
- [x] Auto-sync: Debounced vault sync to server after every mutation
- [x] Vault reload from disk after server pull
- [x] tmux session list auto-refresh (3s timer in session manager dialog)
- [x] tmux quick-switch popup with one-click session switching
- [x] Fix session manager dialog to use runCommand for session listing
- [x] File modularity: Split large files (core_vault, main, terminal_screen) into modules
- [x] Fix all analyzer warnings across ui_terminal and minimal apps
- [x] Keyboard shortcuts: Ctrl+Tab/Shift+Tab for tab cycling, Ctrl+1-9 direct access, Ctrl+T new connection, Ctrl+W close tab
- [x] Snippets UI: Full CRUD in Hosts screen, snippet picker in terminal status bar
- [x] Android extra-key row: Scrollable bar with arrows, Ctrl combos, navigation, special characters
- [x] Fix all 36 analyzer warnings (deprecated APIs, unused imports, dead code)
- [x] Terminal theme customization (12 themes)
- [x] App-wide theming based on terminal theme
- [x] tmux auto-attach on connection
- [x] tmux session picker when multiple sessions exist
- [x] tmux session manager UI
- [x] Show tmux session name in tab header
- [x] New vertical sidebar UI
- [x] Custom app icon
- [x] Settings dialog with Appearance and SSH tabs
- [x] SSH settings (keepalive, timeout, default port)
- [x] Apply SSH keepalive settings to actual connections
- [x] Auto-reconnect with exponential backoff
- [x] Import SSH keys from ~/.ssh
- [x] Key fingerprint display for identities
- [x] Reconnect button for disconnected tabs
- [x] Multi-tab terminal with independent connections
- [x] Password and key authentication
- [x] Encrypted vault with auto-unlock
- [x] Host key verification and trust management

## Planned

### Medium Priority

- [ ] **Session recording**: Record and playback terminal sessions
- [ ] **Search in terminal**: Find text in terminal output
- [ ] **Split panes**: Multiple terminals in one tab
- [ ] **Port forwarding UI**: Local/Remote port forwarding with GUI
- [ ] **SSH agent forwarding**: Forward SSH agent for Git operations on remote servers

### Low Priority

- [ ] **Scrypt KDF**: Implement or remove `KdfKind.scrypt` enum value
- [ ] **State management**: Consider Riverpod/Bloc as complexity grows
- [ ] **iOS/macOS support**: Add Apple platform targets
- [ ] **Localization**: Multi-language support
- [ ] **Terminal font preview**: Font preview in terminal settings
- [ ] **Export/Import vault**: Export hosts and identities as encrypted backup
- [ ] **Connection health indicator**: Latency display in status bar (ping time)

## Known Issues

### Windows Platform

| Issue | Status | Notes |
|-------|--------|-------|
| xterm focus errors | Open | `PlatformException: view ID is null` in debug console. Cosmetic only, doesn't affect functionality. Known xterm/Flutter Windows issue. |

### SSH Authentication

| Issue | Status | Notes |
|-------|--------|-------|
| Key auth silent failure | Documented | If vault key differs from server's authorized key, auth fails silently. Workaround: Use password auth or import correct key. |

## Debugging Tips

### SSH Authentication

Check console for:
```
[SSH-DEBUG] User: username
[SSH-DEBUG] Host: hostname:port
[SSH-DEBUG] Key: -----BEGIN OPENSSH... (first 50 chars)
[SSH-DEBUG] Password provided: true/false
[SSH:Host] Loaded N key(s) from private key
[SSH:Host] Auth methods: key=true/false, password=true/false
```

If key auth fails but `ssh -vv user@host` works from terminal, the vault contains a different key. Import the correct key from `~/.ssh/`.

### Windows xterm Errors

These errors are cosmetic:
```
PlatformException(Bad Arguments, Could not set client, view ID is null., null, null)
PlatformException(Internal Consistency Error, Set editing state has been invoked, but no client is set., null, null)
```

Related to Flutter text input on Windows. Terminal functionality is not affected.

## Feature Requests

Have an idea? Open an issue on GitHub!

## Contributing

See [README.md](README.md#contributing) for contribution guidelines.
