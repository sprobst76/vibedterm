import 'dart:async';
import 'dart:convert';
import 'dart:io';

import 'package:xterm/xterm.dart' as xterm;

import 'js_channel_protocol.dart';

/// Bridges SSH streams to a terminal display.
///
/// On non-Linux platforms, communicates with xterm.js running in a WebView
/// via JavaScript channels. On Linux, falls back to the Dart xterm package.
class TerminalBridge {
  TerminalBridge() {
    if (Platform.isLinux) {
      _nativeTerminal = xterm.Terminal(maxLines: 2000);
      _nativeController = xterm.TerminalController();
      _nativeTerminal!.onOutput = (data) {
        onOutput?.call(data);
      };
      _cols = _nativeTerminal!.viewWidth;
      _rows = _nativeTerminal!.viewHeight;
      _ready = true;
      _readyCompleter.complete();
    }
  }

  // ---------------------------------------------------------------------------
  // Native xterm (Linux fallback)
  // ---------------------------------------------------------------------------

  xterm.Terminal? _nativeTerminal;
  xterm.TerminalController? _nativeController;

  /// The underlying native xterm Terminal (only available on Linux).
  xterm.Terminal? get nativeTerminal => _nativeTerminal;

  /// The native terminal controller (only available on Linux).
  xterm.TerminalController? get nativeController => _nativeController;

  /// Whether this bridge uses the native Dart xterm package (Linux).
  bool get isNative => _nativeTerminal != null;

  // ---------------------------------------------------------------------------
  // Dimensions
  // ---------------------------------------------------------------------------

  int _cols = 80;
  int _rows = 24;

  /// Current terminal width in columns.
  int get viewWidth => _cols;

  /// Current terminal height in rows.
  int get viewHeight => _rows;

  // ---------------------------------------------------------------------------
  // Ready state
  // ---------------------------------------------------------------------------

  bool _ready = false;
  final Completer<void> _readyCompleter = Completer<void>();

  /// Whether the terminal backend is ready to receive data.
  bool get isReady => _ready;

  /// Completes when the terminal backend is initialized and dimensions are known.
  Future<void> get ready => _readyCompleter.future;

  // ---------------------------------------------------------------------------
  // Callbacks
  // ---------------------------------------------------------------------------

  /// Callback invoked when the user types into the terminal.
  void Function(String data)? onOutput;

  /// Callback invoked when the terminal is resized.
  void Function(int cols, int rows)? onResize;

  // ---------------------------------------------------------------------------
  // WebView communication
  // ---------------------------------------------------------------------------

  Future<void> Function(String jsonMessage)? _sendToJs;
  final List<String> _pendingWrites = [];

  /// Called by WebViewTerminalView to wire up JS communication.
  void attachWebView(Future<void> Function(String jsonMessage) sendToJs) {
    _sendToJs = sendToJs;
    for (final data in _pendingWrites) {
      _sendToJs!(jsonEncode({
        'type': JsChannelProtocol.write,
        'data': data,
      }));
    }
    _pendingWrites.clear();
  }

  /// Called by WebViewTerminalView when a message arrives from JavaScript.
  void handleJsMessage(Map<String, dynamic> msg) {
    switch (msg['type']) {
      case JsChannelProtocol.ready:
        _cols = msg['cols'] as int;
        _rows = msg['rows'] as int;
        _ready = true;
        if (!_readyCompleter.isCompleted) {
          _readyCompleter.complete();
        }
        break;
      case JsChannelProtocol.input:
        onOutput?.call(msg['data'] as String);
        break;
      case JsChannelProtocol.resize:
        _cols = msg['cols'] as int;
        _rows = msg['rows'] as int;
        onResize?.call(_cols, _rows);
        break;
      case JsChannelProtocol.selection:
        _selectionCompleter?.complete(msg['text'] as String?);
        break;
    }
  }

  // ---------------------------------------------------------------------------
  // Stream attachment
  // ---------------------------------------------------------------------------

  final List<StreamSubscription<List<int>>> _subscriptions = [];

  /// Attaches SSH stdout/stderr streams to the terminal display.
  void attachStreams({
    required Stream<List<int>> stdout,
    required Stream<List<int>> stderr,
  }) {
    _cancelSubscriptions();
    _subscriptions.add(
      stdout.listen(
          (data) => write(utf8.decode(data, allowMalformed: true))),
    );
    _subscriptions.add(
      stderr.listen(
          (data) => write(utf8.decode(data, allowMalformed: true))),
    );
  }

  // ---------------------------------------------------------------------------
  // Terminal operations
  // ---------------------------------------------------------------------------

  /// Write string data to the terminal display.
  void write(String data) {
    if (isNative) {
      _nativeTerminal!.write(data);
      return;
    }
    if (_sendToJs != null && _ready) {
      _sendToJs!(jsonEncode({
        'type': JsChannelProtocol.write,
        'data': data,
      }));
    } else {
      _pendingWrites.add(data);
    }
  }

  /// Clear terminal buffer and reset cursor position.
  void resetTerminal() {
    if (isNative) {
      _nativeTerminal!.buffer.clear();
      _nativeTerminal!.buffer.setCursor(0, 0);
      return;
    }
    _sendToJs?.call(jsonEncode({'type': JsChannelProtocol.reset}));
  }

  /// Trigger a refit of the terminal to its container.
  void fit() {
    if (isNative) return; // Native handles sizing via TerminalView
    _sendToJs?.call(jsonEncode({'type': JsChannelProtocol.fit}));
  }

  /// Request the terminal to take focus.
  void focus() {
    if (isNative) return; // Native uses FocusNode
    _sendToJs?.call(jsonEncode({'type': JsChannelProtocol.focus}));
  }

  // ---------------------------------------------------------------------------
  // Selection
  // ---------------------------------------------------------------------------

  Completer<String?>? _selectionCompleter;

  /// Get currently selected text. Async on WebView, sync fallback on native.
  Future<String?> getSelectedText() async {
    if (isNative) {
      final selection = _nativeController!.selection;
      if (selection == null) return null;
      return _nativeTerminal!.buffer.getText(selection);
    }
    if (_sendToJs == null) return null;
    _selectionCompleter = Completer<String?>();
    unawaited(_sendToJs!(jsonEncode({'type': JsChannelProtocol.getSelection})));
    return _selectionCompleter!.future.timeout(
      const Duration(seconds: 1),
      onTimeout: () => null,
    );
  }

  /// Clear the current selection.
  void clearSelection() {
    if (isNative) {
      _nativeController!.clearSelection();
      return;
    }
    _sendToJs?.call(jsonEncode({'type': JsChannelProtocol.clearSelection}));
  }

  // ---------------------------------------------------------------------------
  // Configuration (WebView only — native uses widget parameters)
  // ---------------------------------------------------------------------------

  void setTheme(Map<String, String> xtermJsTheme) {
    _sendToJs?.call(jsonEncode({
      'type': JsChannelProtocol.setTheme,
      'theme': xtermJsTheme,
    }));
  }

  void setFontSize(double fontSize) {
    _sendToJs?.call(jsonEncode({
      'type': JsChannelProtocol.setFontSize,
      'fontSize': fontSize,
    }));
  }

  void setFontFamily(String fontFamily) {
    _sendToJs?.call(jsonEncode({
      'type': JsChannelProtocol.setFontFamily,
      'fontFamily': fontFamily,
    }));
  }

  void setCursorStyle(String style) {
    _sendToJs?.call(jsonEncode({
      'type': JsChannelProtocol.setCursorStyle,
      'style': style,
    }));
  }

  void setOpacity(double opacity) {
    _sendToJs?.call(jsonEncode({
      'type': JsChannelProtocol.setOpacity,
      'opacity': opacity,
    }));
  }

  // ---------------------------------------------------------------------------
  // Lifecycle
  // ---------------------------------------------------------------------------

  void dispose() {
    _cancelSubscriptions();
    if (isNative) {
      _nativeTerminal!.onOutput = null;
    } else {
      _sendToJs?.call(jsonEncode({'type': JsChannelProtocol.dispose}));
    }
    onOutput = null;
    onResize = null;
  }

  void _cancelSubscriptions() {
    for (final sub in _subscriptions) {
      sub.cancel();
    }
    _subscriptions.clear();
  }
}
