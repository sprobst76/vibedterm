# Notes / Experiment Log

Summary of experiments and findings while debugging terminal input and selection behavior:

- Initial state: `TerminalView` rendered but IME commits and Enter handling were unreliable.

- Added an overlay `TextField` to capture IME composition and `onSubmitted` commits; this caused `TextEditingController used after being disposed` and Flutter TextInput PlatformExceptions on Windows because of dynamic reparenting.

- Removed premature `dispose()` calls and added autofocus to password dialogs; reduced one class of errors.

- Switched to a persistent overlay approach (inserted post‑frame) to avoid setState/in-build races. This reduced some errors but PlatformExceptions persisted depending on insertion timing.

- Built `minimal_terminal_app` for faster iteration and added logic to auto‑load `config.json` and connect via `core_ssh`.

- Implemented input forwarding path:
  - `RawKeyboardListener` forwards special keys and printable characters to `_shellSession.writeString(...)`.
  - For IME/composed commits we experimented with overlay `TextField` but removed it in the minimal app to avoid reparenting issues; the main app (`ui_terminal`) retains a deferred overlay strategy.

- Implemented explicit special key mappings (Backspace→0x7f, arrows→ANSI escape sequences, Tab, Delete, Home/End, PageUp/PageDown, Ctrl+C).

- Middle‑click paste: implemented by wrapping `TerminalView` with a `Listener` that on middle‑click reads `Clipboard.getData('text/plain')` and writes to shell — this functions correctly.

- Selection→Clipboard: attempted a reflection approach to probe `Terminal`/`Buffer` for selection properties (`selectedText`, `selection`, `getSelectedText()`, `getSelection()` etc.).
  - Runtime inspection shows `terminal.runtimeType=Terminal` and `buffer.runtimeType=Buffer`.
  - Reflection attempts did not reliably return selection text. The implementation added a resilient `TerminalBridge.getSelectedText()` which tries common properties; however, the method did not find a selection in practice in the minimal runs.

- Conclusion: middle‑click paste works; selection→clipboard requires direct knowledge of the exact `xterm` API and a stable read path. The dynamic reflection approach is brittle and incomplete.

Recommended next steps (developer handoff):

1. Inspect the `xterm` package source (local pub cache or package source) to identify the exact method/property that provides selected text from `Terminal` or `Buffer`.
2. Implement a direct accessor in `packages/ui_terminal` (update `TerminalBridge.getSelectedText()` to call the concrete API). Remove reflection fallbacks once the API is known.
3. Consider adding an always‑present, non‑reparenting invisible `TextField` in `VibedTerminalView` to capture IME and avoid Windows TextInput reparenting errors.
4. Add unit/integration tests that automate selection and verify clipboard contents (platform-specific harness).

Logs and recent run outputs were saved to console during experimentation; check the flutter run console for `DEBUG` messages.
