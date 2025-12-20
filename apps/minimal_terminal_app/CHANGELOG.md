# Changelog — minimal_terminal_app

## Unreleased

- Add `xterm` TerminalView integration and `core_ssh` connect logic.
- Implemented keyboard forwarding for printable characters, Enter, Backspace, Tab, Arrow keys, Delete, Home/End, PageUp/PageDown, and Ctrl+C.
- Added middle‑mouse paste (reads clipboard and sends to shell).
- Added extensive console debug logs for input, stdout/stderr, and config load.
- Added experimental reflection-based `getSelectedText()` in `packages/ui_terminal` and `onPointerUp` hook in `VibedTerminalView` to attempt selection→clipboard.

## Notes
- Selecting text currently does not copy to clipboard reliably — further work required to read selection from `xterm` internals or to use `xterm` API directly.
