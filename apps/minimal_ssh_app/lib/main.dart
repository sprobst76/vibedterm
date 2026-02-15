import 'dart:async';
import 'dart:convert';
import 'dart:io';
import 'package:flutter/material.dart';
import 'package:core_ssh/core_ssh.dart';
import 'package:xterm/xterm.dart';
import 'package:flutter/services.dart';

void main() {
  runApp(const MinimalSshApp());
}

class MinimalSshApp extends StatelessWidget {
  const MinimalSshApp({super.key});

  @override
  Widget build(BuildContext context) {
    return const MaterialApp(
      title: 'Minimal SSH App',
      home: Scaffold(
        body: SafeArea(child: SshPage()),
      ),
    );
  }
}

class SshPage extends StatefulWidget {
  const SshPage({super.key});

  @override
  State<SshPage> createState() => _SshPageState();
}

class _SshPageState extends State<SshPage> {
  final SshConnectionManager _mgr = SshConnectionManager();
  final Terminal _terminal = Terminal(maxLines: 2000);
  final TextEditingController _inputController = TextEditingController();
  final ScrollController _scroll = ScrollController();
  final List<String> _lines = [];
  SshShellSession? _session;
  StreamSubscription<String>? _logSub;
  OverlayEntry? _inputOverlay;
  final FocusNode _focusNode = FocusNode();
  bool _activated = false;

  @override
  void initState() {
    super.initState();
    _logSub = _mgr.logs.listen((m) => _appendLine('[LOG] $m'));
    _loadAndConnect();
  }

  Future<void> _loadAndConnect() async {
    try {
      final cfgFile = File(
          '${Directory.current.path.replaceAll('\\', '/')}/apps/minimal_ssh_app/config.json');
      if (!await cfgFile.exists()) {
        _appendLine('config.json not found at ${cfgFile.path}');
        return;
      }
      final raw = await cfgFile.readAsString();
      final map = json.decode(raw) as Map<String, dynamic>;
      final host = map['host'] as String;
      final port = (map['port'] as num?)?.toInt() ?? 22;
      final username = map['username'] as String? ?? '';
      final password = (map['password'] as String?) ?? '';
      String? keyPem;
      final keyfile = (map['privateKeyFile'] as String?) ?? '';
      if (keyfile.isNotEmpty) {
        final f = File(keyfile);
        if (await f.exists()) {
          keyPem = await f.readAsString();
        } else {
          _appendLine('privateKeyFile not found: $keyfile');
        }
      }

      final target = SshTarget(
        host: host,
        port: port,
        username: username,
        password: password.isEmpty ? null : password,
        privateKey: keyPem,
      );

      _appendLine('Connecting to $username@$host:$port...');
      await _mgr.connect(target);
      _appendLine('Connected. Starting shell...');
      _session = await _mgr.startShell();

      _session!.stdout.listen((data) {
        final s = utf8.decode(data);
        _appendLine(s);
      }, onDone: () => _appendLine('[stdout done]'));
      _session!.stderr.listen((data) {
        final s = utf8.decode(data);
        _appendLine('[ERR] $s');
      }, onDone: () => _appendLine('[stderr done]'));

      _appendLine('Shell started. Type in the input box and press Enter.');
      // Write any incoming data into the terminal renderer
      _session!.stdout.listen((data) {
        final s = utf8.decode(data);
        _terminal.write(s);
      }, onDone: () => _appendLine('[stdout done]'));
      _session!.stderr.listen((data) {
        final s = utf8.decode(data);
        _terminal.write('[ERR] $s');
      }, onDone: () => _appendLine('[stderr done]'));
    } catch (e) {
      _appendLine('Connection error: $e');
    }
  }

  void _appendLine(String s) {
    setState(() {
      _lines.add(s);
      // Also write to terminal renderer for visual parity
      _terminal.write('$s\r\n');
      // scroll later
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (_scroll.hasClients) {
          _scroll.jumpTo(_scroll.position.maxScrollExtent);
        }
      });
    });
  }

  Future<void> _sendInput(String text) async {
    if (_session == null) {
      _appendLine('[WARN] not connected');
      return;
    }
    try {
      await _session!.writeString('$text\r');
      _inputController.clear();
    } catch (e) {
      _appendLine('Write error: $e');
    }
  }

  void _activateInput() {
    if (_activated) return;
    _activated = true;
    // create and insert overlay field to capture IME/composed input
    _inputOverlay = OverlayEntry(builder: (ctx) {
      return Positioned(
        left: 0,
        top: 0,
        width: 1,
        height: 1,
        child: Material(
          color: Colors.transparent,
          child: TextField(
            controller: _inputController,
            focusNode: _focusNode,
            autofocus: false,
            showCursor: false,
            enableInteractiveSelection: false,
            decoration: const InputDecoration.collapsed(hintText: ''),
            onChanged: (s) {
              final v = _inputController.value;
              if (v.composing.isValid) return;
              if (s.isNotEmpty) {
                final text = s;
                try {
                  _session?.writeString(text);
                } catch (_) {}
                _inputController.clear();
              }
            },
            onSubmitted: (s) {
              try {
                _session?.writeString('\r');
              } catch (_) {}
              _inputController.clear();
            },
          ),
        ),
      );
    });
    WidgetsBinding.instance.addPostFrameCallback((_) {
      try {
        final overlay = Overlay.of(context);
        overlay.insert(_inputOverlay!);
        _focusNode.requestFocus();
      } catch (_) {}
    });
  }

  @override
  void dispose() {
    _logSub?.cancel();
    _inputController.dispose();
    _scroll.dispose();
    _mgr.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return Focus(
      focusNode: _focusNode,
      onKeyEvent: (node, event) {
        if (event is KeyDownEvent) {
          if (event.logicalKey == LogicalKeyboardKey.enter) {
            _session?.writeString('\r');
            return KeyEventResult.handled;
          }
          if (event.logicalKey == LogicalKeyboardKey.backspace) {
            _session?.writeString('\x7f');
            return KeyEventResult.handled;
          }
          final ch = event.character;
          if (ch != null && ch.isNotEmpty) {
            _session?.writeString(ch);
            return KeyEventResult.handled;
          }
        }
        return KeyEventResult.ignored;
      },
      child: GestureDetector(
        onTap: _activateInput,
        child: Column(
          children: [
            Expanded(
              child: Container(
                color: Colors.black,
                child: TerminalView(
                  _terminal,
                  autofocus: false,
                  padding: const EdgeInsets.all(8),
                ),
              ),
            ),
            Padding(
              padding: const EdgeInsets.all(8.0),
              child: Row(
                children: [
                  Expanded(
                    child: TextField(
                      controller: _inputController,
                      decoration: const InputDecoration(
                          border: OutlineInputBorder(),
                          hintText: 'Type command...'),
                      onSubmitted: (s) => _sendInput(s),
                    ),
                  ),
                  const SizedBox(width: 8),
                  ElevatedButton(
                      onPressed: () => _sendInput(_inputController.text),
                      child: const Text('Send')),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}
