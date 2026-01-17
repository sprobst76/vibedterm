# TODO & Roadmap

## Recently Completed

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
- [x] Multi-tab terminal with independent connections
- [x] Password and key authentication
- [x] Encrypted vault with auto-unlock
- [x] Host key verification and trust management

## In Progress

- [ ] Apply SSH keepalive settings to actual connections
- [ ] Implement auto-reconnect functionality

## Planned

### High Priority

- [ ] **Import from ~/.ssh**: Easy import of existing SSH keys
- [ ] **Key fingerprint display**: Show fingerprint in identity details
- [ ] **Reconnect button**: Quick reconnect for disconnected tabs
- [ ] **tmux session list auto-refresh**: Parse terminal output for session list
- [ ] **Keyboard shortcuts**: Ctrl+Tab for tab switching, Ctrl+1-9 for direct access

### Medium Priority

- [ ] **Snippets UI**: Manage `VaultSnippet` entries (model exists, no UI)
- [ ] **Android extra-key row**: Special keys in terminal status bar for mobile
- [ ] **Session recording**: Record and playback terminal sessions
- [ ] **SFTP file browser**: Browse and transfer files via SFTP
- [ ] **Search in terminal**: Find text in terminal output
- [ ] **Split panes**: Multiple terminals in one tab

### Low Priority

- [ ] **Scrypt KDF**: Implement or remove `KdfKind.scrypt` enum value
- [ ] **State management**: Consider Riverpod/Bloc as complexity grows
- [ ] **Cloud sync**: Implement `core_sync` for OneDrive/Google Drive vault sync
- [ ] **iOS/macOS support**: Add Apple platform targets
- [ ] **Localization**: Multi-language support

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
