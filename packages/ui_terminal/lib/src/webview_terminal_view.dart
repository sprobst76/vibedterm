import 'dart:convert';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_inappwebview/flutter_inappwebview.dart';

import 'terminal_bridge.dart';
import 'theme_presets.dart';

/// Terminal view using xterm.js in an InAppWebView (Windows, Android, iOS, macOS).
class WebViewTerminalView extends StatefulWidget {
  const WebViewTerminalView({
    super.key,
    required this.bridge,
    this.themeName = 'default',
    this.fontSize = 14.0,
    this.fontFamily,
    this.opacity = 1.0,
    this.cursorStyle = TerminalCursorStyle.block,
  });

  final TerminalBridge bridge;
  final String themeName;
  final double fontSize;
  final String? fontFamily;
  final double opacity;
  final TerminalCursorStyle cursorStyle;

  @override
  State<WebViewTerminalView> createState() => _WebViewTerminalViewState();
}

class _WebViewTerminalViewState extends State<WebViewTerminalView> {
  bool _webViewReady = false;
  String? _htmlContent;

  @override
  void initState() {
    super.initState();
    _loadHtmlContent();
  }

  Future<void> _loadHtmlContent() async {
    // Load the HTML template and JS/CSS assets from the package bundle
    final html = await rootBundle
        .loadString('packages/ui_terminal/assets/terminal.html');
    final xtermJs =
        await rootBundle.loadString('packages/ui_terminal/assets/xterm.js');
    final xtermCss =
        await rootBundle.loadString('packages/ui_terminal/assets/xterm.css');
    final fitJs = await rootBundle
        .loadString('packages/ui_terminal/assets/xterm-addon-fit.js');

    // Inline the JS and CSS into the HTML to avoid cross-origin issues
    final inlinedHtml = html
        .replaceFirst(
          '<link rel="stylesheet" href="xterm.css">',
          '<style>$xtermCss</style>',
        )
        .replaceFirst(
          '<script src="xterm.js"></script>',
          '<script>$xtermJs</script>',
        )
        .replaceFirst(
          '<script src="xterm-addon-fit.js"></script>',
          '<script>$fitJs</script>',
        );

    if (mounted) {
      setState(() {
        _htmlContent = inlinedHtml;
      });
    }
  }

  @override
  void didUpdateWidget(WebViewTerminalView old) {
    super.didUpdateWidget(old);
    if (!_webViewReady) return;

    if (old.themeName != widget.themeName) {
      _applyTheme();
    }
    if (old.fontSize != widget.fontSize) {
      widget.bridge.setFontSize(widget.fontSize);
    }
    if (old.fontFamily != widget.fontFamily) {
      widget.bridge.setFontFamily(widget.fontFamily ?? 'monospace');
    }
    if (old.opacity != widget.opacity) {
      widget.bridge.setOpacity(widget.opacity);
    }
    if (old.cursorStyle != widget.cursorStyle) {
      widget.bridge
          .setCursorStyle(_cursorStyleString(widget.cursorStyle));
    }
  }

  void _applyTheme() {
    final theme = TerminalThemePresets.getTheme(widget.themeName);
    widget.bridge.setTheme(theme.toXtermJsTheme());
  }

  String _cursorStyleString(TerminalCursorStyle style) {
    switch (style) {
      case TerminalCursorStyle.block:
        return 'block';
      case TerminalCursorStyle.underline:
        return 'underline';
      case TerminalCursorStyle.bar:
        return 'bar';
    }
  }

  @override
  Widget build(BuildContext context) {
    if (_htmlContent == null) {
      // Still loading assets
      return const Center(child: CircularProgressIndicator.adaptive());
    }

    return InAppWebView(
      initialData: InAppWebViewInitialData(
        data: _htmlContent!,
        mimeType: 'text/html',
        encoding: 'utf-8',
      ),
      initialSettings: InAppWebViewSettings(
        javaScriptEnabled: true,
        transparentBackground: true,
        disableContextMenu: true,
        supportZoom: false,
        useHybridComposition: true,
        allowsBackForwardNavigationGestures: false,
        isInspectable: false,
      ),
      onWebViewCreated: (controller) {
        // Register handler for messages from xterm.js
        controller.addJavaScriptHandler(
          handlerName: 'dartChannel',
          callback: (args) {
            if (args.isEmpty) return;
            final msg =
                jsonDecode(args[0] as String) as Map<String, dynamic>;
            widget.bridge.handleJsMessage(msg);

            // On ready, push initial configuration
            if (msg['type'] == 'ready') {
              _webViewReady = true;
              _applyTheme();
              widget.bridge.setFontSize(widget.fontSize);
              widget.bridge
                  .setFontFamily(widget.fontFamily ?? 'monospace');
              widget.bridge.setCursorStyle(
                  _cursorStyleString(widget.cursorStyle));
              widget.bridge.setOpacity(widget.opacity);
            }
          },
        );

        // Wire up bridge → JS communication
        widget.bridge.attachWebView((jsonMessage) async {
          // jsonMessage is already a JSON string; we need to pass it
          // as a string argument to handleDartMessage in JS.
          final escaped =
              jsonMessage.replaceAll('\\', '\\\\').replaceAll("'", "\\'");
          await controller.evaluateJavascript(
            source: "handleDartMessage('$escaped');",
          );
        });
      },
    );
  }

  @override
  void dispose() {
    super.dispose();
  }
}
