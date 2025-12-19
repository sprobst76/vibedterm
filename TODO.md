# TODO

## Completed

- ~~Wire terminal screen to xterm for interactive shells, including resize and Android extra-key row.~~
- ~~Add host-key trust list management UI (view/remove) and per-host fingerprints display.~~
- ~~Surface vault identities' passphrases and agent support when connecting hosts.~~
- ~~Terminus-like multi-tab terminal with independent connections per tab.~~
- ~~Password authentication support with dialog prompt.~~
- ~~Auto-unlock vault on startup if password saved securely.~~
- ~~Enter key to confirm password dialogs.~~
- ~~Debug logging for SSH auth (user, host, key preview, auth methods).~~

## In Progress

- Root-level `flutter test` script via Melos to skip missing top-level tests gracefully.

## Known Issues (Windows)

- **xterm PlatformException**: `Could not set client, view ID is null` errors appear in debug console. This is a known Flutter/xterm issue on Windows - doesn't block functionality but is annoying. Attempted fixes:
  - Disabled `autofocus` on `VibedTerminalView`
  - Added 100ms delay before `focusNode.requestFocus()`
  - Errors still occur but terminal works

- **SSH Key Auth Fails**: If the private key stored in the vault is different from the one authorized on the server, key auth fails silently. Workaround: Use password auth or import the correct key (the one from `~/.ssh/` that works with command-line SSH).

## Planned

### High Priority

- Investigate xterm Windows focus issue more thoroughly (may need upstream fix).
- Add "Import from ~/.ssh" feature to easily import existing SSH keys.
- Show key fingerprint in identity details for easier verification.
- Add reconnect button for disconnected/error tabs.

### Medium Priority

- Implement `KdfKind.scrypt` or remove from enum (currently throws "not implemented").
- Add UI for managing `VaultSnippet` (model exists, no UI yet).
- Apply `VaultSettings` (theme, fontSize, extraKeys) to terminal view.
- Keyboard shortcuts for tab switching (Ctrl+Tab, Ctrl+1-9).
- Android extra-key row in terminal status bar.

### Low Priority

- Widget tests for screens.
- Consider Riverpod/Bloc for state management as complexity grows.
- SFTP file browser integration.
- Session recording/playback.

## Debugging Notes

### SSH Authentication Debugging

When SSH key auth fails, check the console for:
```
[SSH-DEBUG] User: username
[SSH-DEBUG] Host: hostname:port
[SSH-DEBUG] Key: -----BEGIN OPENSSH... (first 50 chars)
[SSH-DEBUG] Password provided: true/false
[SSH:Host] Loaded N key(s) from private key
[SSH:Host] Auth methods: key=true/false, password=true/false
```

If key auth fails but command-line `ssh -vv user@host` works, the vault contains a different key than `~/.ssh/id_*`. Solution: Import the correct key into the vault.

### Windows xterm Errors

These errors are cosmetic and don't break functionality:
```
PlatformException(Bad Arguments, Could not set client, view ID is null., null, null)
PlatformException(Internal Consistency Error, Set editing state has been invoked, but no client is set., null, null)
```

Related to Flutter text input system on Windows. The xterm package has known issues with Windows platform.
