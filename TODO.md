# TODO

## Completed

- ~~Wire terminal screen to xterm for interactive shells, including resize and Android extra-key row.~~
- ~~Add host-key trust list management UI (view/remove) and per-host fingerprints display.~~
- ~~Surface vault identities' passphrases and agent support when connecting hosts.~~

## In Progress

- Root-level `flutter test` script via Melos to skip missing top-level tests gracefully.

## Planned

- Implement `KdfKind.scrypt` or remove from enum (currently throws "not implemented").
- Add UI for managing `VaultSnippet` (model exists, no UI yet).
- Apply `VaultSettings` (theme, fontSize, extraKeys) to terminal view.
- Add reconnect button for disconnected/error tabs.
- Keyboard shortcuts for tab switching (Ctrl+Tab, Ctrl+1-9).
- Android extra-key row in terminal status bar.
- Widget tests for screens.
- Consider Riverpod/Bloc for state management as complexity grows.
