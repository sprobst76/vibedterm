# Minimal Terminal App

Purpose
- Minimal Flutter app used to reproduce and debug terminal input, IME, and SSH integration using the `xterm` package and local `core_ssh`.

How to run (Windows)
```powershell
cd C:/Development/Projects/vibedterm/apps/minimal_terminal_app
flutter pub get
flutter run -d windows
```

Config
- `config.json` in the app folder is read (or searched for in likely parent locations). Fields:
  - `host` (required)
  - `port` (default 22)
  - `username` (required)
  - `password` (optional)
  - `privateKeyFile` (optional, absolute path)
  - `passphrase` (optional)
  - `keepAliveSeconds` (optional)

What this app demonstrates
- Terminal rendering with `xterm` (`TerminalView`).
- SSH connect using `packages/core_ssh` and an interactive PTY shell.
- Keyboard forwarding (printable chars, Enter, Backspace, Tab, Arrow keys, Ctrl+C).
- Middle‑mouse paste from clipboard (X11 style) works.

Current limitations
- Selecting text in the terminal does not reliably copy to the system clipboard yet. See `NOTES.md` for details and experiments.

Next steps (short)
- Determine exact `xterm` selection API and implement `getSelectedText()` in `packages/ui_terminal`.
- Add a persistent invisible `TextField` (non‑reparenting) for robust IME handling if needed.

Files of interest
- `lib/main.dart` — minimal app logic and input handling.
- `config.json` — connection settings.
- `packages/ui_terminal/lib/ui_terminal.dart` — TerminalBridge and `VibedTerminalView` used in the main app.

Contact
- This workspace contains the main project; continue the work in `apps/ssh_client_app` or in the `packages/ui_terminal` package as appropriate.
Minimal Terminal App

This minimal Flutter app reproduces IME/Enter handling with an xterm Terminal
and an invisible overlay `TextField` to capture composed input.

Run:

```bash
cd apps/minimal_terminal_app
flutter pub get
flutter run -d windows
```

Behavior:
- Type characters: they are echoed locally into the terminal.
- Press Enter: the app simulates executing the line and prints `You typed: ...`.

Use this to compare input handling with your main app's overlay approach.
