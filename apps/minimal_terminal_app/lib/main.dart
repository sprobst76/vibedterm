import 'package:flutter/material.dart';
import 'package:flutter/gestures.dart';
import 'package:flutter/services.dart';
import 'dart:convert';
import 'dart:io';

import 'package:xterm/xterm.dart';
import 'package:core_ssh/core_ssh.dart';

void main() {
  runApp(const MinimalTerminalApp());
}

class MinimalTerminalApp extends StatelessWidget {
  const MinimalTerminalApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Minimal Terminal',
      home: const Scaffold(
        body: SafeArea(child: TerminalPage()),
      ),
    );
  }
}

class TerminalPage extends StatefulWidget {
  const TerminalPage({super.key});

  @override
  State<TerminalPage> createState() => _TerminalPageState();
}

class _TerminalPageState extends State<TerminalPage> {
  final Terminal _terminal = Terminal(maxLines: 1000);
  SshConnectionManager? _connManager;
  SshShellSession? _shellSession;
  final TextEditingController _inputController = TextEditingController();
  final FocusNode _inputFocus = FocusNode();
  final FocusNode _outerFocus = FocusNode();
  OverlayEntry? _inputOverlay;
  bool _composing = false;
  String _currentBuffer = '';

  @override
  void initState() {
    super.initState();
    _terminal.write('Welcome to minimal terminal\r\n');
    // debug
    _debug('initState start');
    _terminal.write('Type something and press Enter.\r\n> ');
    // No overlay TextField here — use RawKeyboardListener to forward keys to SSH.
    // Try load config and connect via SSH
    WidgetsBinding.instance.addPostFrameCallback((_) async {
      await _tryConnectFromConfig();
    });
    _debug('post frame callback scheduled for config load');
    // Echo terminal output when terminal.onOutput is used by xterm, not needed here.
  }

  @override
  void dispose() {
    _inputOverlay?.remove();
    _inputController.dispose();
    _inputFocus.dispose();
    _outerFocus.dispose();
    super.dispose();
  }

  void _handleRawKey(RawKeyEvent event) {
    if (event is! RawKeyDownEvent) return;
    _debug(
        'RawKeyEvent: runtimeType=${event.runtimeType}, logical=${event.logicalKey.debugName}, keyId=${event.logicalKey.keyId}, char=${event.character}, ctrl=${event.isControlPressed}, alt=${event.isAltPressed}, meta=${event.isMetaPressed}');

    // Handle common control sequences
    // Ctrl+C
    if (event.isControlPressed && event.logicalKey == LogicalKeyboardKey.keyC) {
      _debug('Ctrl+C pressed');
      if (_shellSession != null) {
        _shellSession!.writeString('\x03');
      }
      return;
    }

    // Enter
    if (event.logicalKey == LogicalKeyboardKey.enter) {
      if (_shellSession != null) {
        _debug('sending CR to shellSession');
        _shellSession!.writeString('\r');
      } else {
        _debug('no shellSession: submitting line locally');
        _submitLine();
      }
      return;
    }

    // Backspace
    if (event.logicalKey == LogicalKeyboardKey.backspace) {
      _debug('Backspace');
      if (_shellSession != null) {
        _shellSession!.writeString('\x7f');
      } else {
        if (_currentBuffer.isNotEmpty) {
          _currentBuffer =
              _currentBuffer.substring(0, _currentBuffer.length - 1);
          // simple visual backspace
          _terminal.write('\b \b');
        }
      }
      return;
    }

    // Tab
    if (event.logicalKey == LogicalKeyboardKey.tab) {
      _debug('Tab');
      if (_shellSession != null) {
        _shellSession!.writeString('\t');
      } else {
        _currentBuffer += '\t';
        _terminal.write('\t');
      }
      return;
    }

    // Arrow keys & other navigation
    if (event.logicalKey == LogicalKeyboardKey.arrowUp) {
      _debug('ArrowUp');
      if (_shellSession != null) _shellSession!.writeString('\x1b[A');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowDown) {
      _debug('ArrowDown');
      if (_shellSession != null) _shellSession!.writeString('\x1b[B');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowRight) {
      _debug('ArrowRight');
      if (_shellSession != null) _shellSession!.writeString('\x1b[C');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.arrowLeft) {
      _debug('ArrowLeft');
      if (_shellSession != null) _shellSession!.writeString('\x1b[D');
      return;
    }

    // Delete
    if (event.logicalKey == LogicalKeyboardKey.delete) {
      _debug('Delete');
      if (_shellSession != null) _shellSession!.writeString('\x1b[3~');
      return;
    }

    // Home / End / PageUp / PageDown
    if (event.logicalKey == LogicalKeyboardKey.home) {
      if (_shellSession != null) _shellSession!.writeString('\x1b[H');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.end) {
      if (_shellSession != null) _shellSession!.writeString('\x1b[F');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageUp) {
      if (_shellSession != null) _shellSession!.writeString('\x1b[5~');
      return;
    }
    if (event.logicalKey == LogicalKeyboardKey.pageDown) {
      if (_shellSession != null) _shellSession!.writeString('\x1b[6~');
      return;
    }

    // Printable characters
    if (event.character != null && event.character!.isNotEmpty) {
      final ch = event.character!;
      _debug('char input: "$ch"');
      if (_shellSession != null) {
        _debug('forwarding char to shellSession');
        _shellSession!.writeString(ch);
      } else {
        _debug('local echo');
        _currentBuffer += ch;
        _terminal.write(ch);
      }
    }
  }

  void _submitLine() {
    final cmd = _currentBuffer;
    _currentBuffer = '';
    // Move to new line
    _terminal.write('\r\n');
    // Simulate executing the command
    _terminal.write('You typed: $cmd\r\n');
    // Prompt
    _terminal.write('> ');
    // Clear overlay input
    _inputController.clear();
    // keep focus
    _inputFocus.requestFocus();
  }

  Future<void> _tryConnectFromConfig() async {
    try {
      _debug('trying to locate config.json');
      String _findConfigPath() {
        final base = Directory.current.path.replaceAll('\\', '/');
        final candidates = <String>{};
        candidates.add('$base/config.json');
        // Common project-relative location
        candidates.add('$base/apps/minimal_terminal_app/config.json');
        // Try parent directories in case Directory.current already points into the app folder
        final parent = Directory(base).parent.path.replaceAll('\\', '/');
        candidates.add('$parent/apps/minimal_terminal_app/config.json');
        final parent2 = Directory(parent).parent.path.replaceAll('\\', '/');
        candidates.add('$parent2/apps/minimal_terminal_app/config.json');

        for (final c in candidates) {
          final f = File(c);
          if (f.existsSync()) return c;
        }
        // fallback to base/config.json
        return '$base/config.json';
      }

      final cfgPath = _findConfigPath();
      _debug('config path resolved to: $cfgPath');
      final cfgFile = File(cfgPath);
      if (!cfgFile.existsSync()) {
        _terminal.write('config.json not found at $cfgPath\r\n');
        _debug('config.json does not exist at resolved path');
        return;
      }
      final raw = cfgFile.readAsStringSync();
      _debug('config.json contents:\n$raw');
      final js = jsonDecode(raw);
      final host = js['host'] as String?;
      final port = js['port'] as int? ?? 22;
      final username = js['username'] as String?;
      final password = (js['password'] as String?)?.isEmpty ?? true
          ? null
          : js['password'] as String?;
      String? privateKey;
      if (js['privateKeyFile'] != null &&
          (js['privateKeyFile'] as String).isNotEmpty) {
        final pkf = File(js['privateKeyFile'] as String);
        if (pkf.existsSync()) {
          privateKey = pkf.readAsStringSync();
        }
      }
      final keepAlive = js['keepAliveSeconds'] is int
          ? Duration(seconds: js['keepAliveSeconds'] as int)
          : const Duration(seconds: 10);

      if (host == null || username == null) {
        _terminal.write('Invalid config.json: host/username required\r\n');
        _debug('invalid config.json: host or username missing');
        return;
      }

      _terminal.write('Connecting to $username@$host:$port ...\r\n');
      _debug('attempting SSH connect to $username@$host:$port');
      _connManager = SshConnectionManager();
      try {
        await _connManager!.connect(SshTarget(
          host: host,
          port: port,
          username: username,
          password: password,
          privateKey: privateKey,
          passphrase: js['passphrase'] as String?,
          keepAliveInterval: keepAlive,
        ));
      } catch (e, st) {
        _terminal.write('SSH connect failed: $e\r\n');
        _debug('SSH connect exception: $e\n$st');
        rethrow;
      }
      _terminal.write('Connected, starting shell...\r\n');
      _debug('connected — starting shell');
      _shellSession = await _connManager!
          .startShell(ptyConfig: SshPtyConfig(width: 80, height: 24));

      _shellSession!.stdout.listen((data) {
        _debug('stdout chunk length=${data.length}');
        try {
          final s = utf8.decode(data);
          _terminal.write(s);
        } catch (e, st) {
          _debug('stdout decode error: $e\n$st');
        }
      });
      _shellSession!.stderr.listen((data) {
        _debug('stderr chunk length=${data.length}');
        try {
          final s = utf8.decode(data);
          _terminal.write(s);
        } catch (e, st) {
          _debug('stderr decode error: $e\n$st');
        }
      });

      _terminal.write('Shell started. Type to send input.\r\n');
      _debug('requesting focus on outer focus node');
      _outerFocus.requestFocus();
    } catch (e) {
      _terminal.write('SSH connect error: $e\r\n');
      _debug('general exception in _tryConnectFromConfig: $e');
    }
  }

  void _debug(String msg) {
    final ts = DateTime.now().toIso8601String();
    final line = 'DEBUG $ts | $msg';
    // Only print to console for flutter run logs
    // ignore: avoid_print
    print(line);
  }

  @override
  Widget build(BuildContext context) {
    return RawKeyboardListener(
      focusNode: _outerFocus,
      onKey: (e) => _handleRawKey(e),
      child: Stack(
        children: [
          Expanded(
            child: Container(
              color: Colors.black,
              child: Listener(
                behavior: HitTestBehavior.opaque,
                onPointerDown: (event) async {
                  // Middle-click paste (typical X11 behaviour)
                  try {
                    if (event.kind == PointerDeviceKind.mouse &&
                        event.buttons == kMiddleMouseButton) {
                      _debug('middle-click detected: pasting from clipboard');
                      final data = await Clipboard.getData('text/plain');
                      final text = data?.text ?? '';
                      if (text.isNotEmpty) {
                        if (_shellSession != null) {
                          _shellSession!.writeString(text);
                        } else {
                          _terminal.write(text);
                        }
                      }
                    }
                  } catch (e) {
                    _debug('middle-click paste error: $e');
                  }
                },
                onPointerUp: (event) async {
                  // Try to copy any terminal selection to clipboard on mouse release.
                  try {
                    if (event.kind == PointerDeviceKind.mouse) {
                      String? selected;
                      try {
                        // Attempt several possible xterm selection accessors via dynamic calls.
                        final t = _terminal as dynamic;
                        final tries = <String>[
                          'selectedText',
                          'selection',
                          'selectionText',
                          'getSelectedText',
                          'getSelection',
                          'getSelectionText',
                        ];
                        for (final name in tries) {
                          try {
                            final res = (t as dynamic).__get ?? null;
                            // Try using dynamic invocation by name
                            dynamic val;
                            try {
                              // property access
                              val = (t as dynamic).noSuchMethod(
                                  Invocation.getter(Symbol(name)));
                            } catch (_) {
                              try {
                                // method call
                                val = (t as dynamic).noSuchMethod(
                                    Invocation.method(Symbol(name), []));
                              } catch (_) {
                                val = null;
                              }
                            }
                            if (val == null) continue;
                            // If this val is a selection object, attempt common methods
                            if (val is String) {
                              selected = val;
                              _debug('selection via $name (string)');
                              break;
                            }
                            try {
                              // try common getters on selection object
                              if ((val as dynamic).text != null) {
                                selected = (val as dynamic).text as String?;
                                if (selected != null && selected.isNotEmpty) {
                                  _debug('selection via $name.text');
                                  break;
                                }
                              }
                            } catch (_) {}
                            try {
                              final maybe = (val as dynamic).toString();
                              if (maybe != null && maybe.isNotEmpty) {
                                selected = maybe as String;
                                _debug('selection via $name.toString()');
                                break;
                              }
                            } catch (_) {}
                          } catch (e) {
                            // ignore individual attempt errors
                          }
                        }
                      } catch (e) {
                        _debug('selection reflection attempts failed: $e');
                      }
                      // If still no selection found, log inspection of terminal/buffer
                      if (selected == null || selected.isEmpty) {
                        try {
                          final t = _terminal as dynamic;
                          _debug('terminal.runtimeType=${t.runtimeType}');
                          try {
                            final buf = t.buffer as dynamic;
                            _debug('buffer.runtimeType=${buf.runtimeType}');
                            try {
                              final vw = t.viewWidth;
                              final vh = t.viewHeight;
                              _debug('viewWidth=$vw viewHeight=$vh');
                            } catch (_) {}
                            // Try some common buffer accessors
                            final candidates = <String>[
                              'lines',
                              'length',
                              'rows',
                              'getLine',
                              'getRow',
                              'getRowText',
                              'toString'
                            ];
                            for (final name in candidates) {
                              try {
                                dynamic val;
                                try {
                                  val = (buf as dynamic).noSuchMethod(
                                      Invocation.getter(Symbol(name)));
                                } catch (_) {
                                  try {
                                    val = (buf as dynamic).noSuchMethod(
                                        Invocation.method(Symbol(name), [0]));
                                  } catch (_) {
                                    val = null;
                                  }
                                }
                                if (val != null) {
                                  _debug(
                                      'buffer has $name -> ${val.runtimeType}');
                                }
                              } catch (_) {}
                            }
                          } catch (e) {
                            _debug('buffer inspection failed: $e');
                          }
                        } catch (e) {
                          _debug('terminal inspection failed: $e');
                        }
                      }
                      if (selected != null && selected.isNotEmpty) {
                        await Clipboard.setData(ClipboardData(text: selected));
                        _debug(
                            'copied selection length=${selected.length} to clipboard');
                      }
                    }
                  } catch (e) {
                    _debug('selection copy error: $e');
                  }
                },
                child: TerminalView(
                  _terminal,
                  autofocus: true,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
          ),
          // Persistent overlay TextField is inserted post-frame; nothing here.
        ],
      ),
    );
  }
}
