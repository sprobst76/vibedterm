# TODO — minimal_terminal_app

Priority: High
- Determine the exact selection API provided by `xterm` (`Terminal`/`Buffer`) and implement a robust `getSelectedText()` in `packages/ui_terminal`.
- Add tests (manual/automated) that verify copying selection to clipboard and pasting with middle‑click.

Priority: Medium
- Implement an always‑present invisible `TextField` for IME composition to avoid reparenting (instead of dynamic overlay insertion).
- Harden focus/timing logic for `TerminalView` initialization on Windows to avoid TextInput PlatformExceptions.

Priority: Low
- Add UI for manual copy/paste (context menu, toolbar buttons) as a fallback on platforms where selection→clipboard is unreliable.
- Add integration into the main `ssh_client_app` and remove experimental code from the minimal app.

Notes
- See `NOTES.md` for experiments and rationale.
- Keep `CHANGELOG.md` updated with test/implementation status.
