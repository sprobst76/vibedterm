/// Message type constants for Dart ↔ xterm.js WebView communication.
abstract class JsChannelProtocol {
  // Dart → JavaScript message types
  static const String write = 'write';
  static const String setTheme = 'setTheme';
  static const String setFontSize = 'setFontSize';
  static const String setFontFamily = 'setFontFamily';
  static const String setCursorStyle = 'setCursorStyle';
  static const String setOpacity = 'setOpacity';
  static const String fit = 'fit';
  static const String clear = 'clear';
  static const String reset = 'reset';
  static const String getSelection = 'getSelection';
  static const String clearSelection = 'clearSelection';
  static const String getDimensions = 'getDimensions';
  static const String focus = 'focus';
  static const String blur = 'blur';
  static const String scrollToBottom = 'scrollToBottom';
  static const String dispose = 'dispose';
  static const String searchNext = 'searchNext';
  static const String searchPrevious = 'searchPrevious';
  static const String clearSearch = 'clearSearch';

  // JavaScript → Dart message types
  static const String ready = 'ready';
  static const String input = 'input';
  static const String resize = 'resize';
  static const String selection = 'selection';
  static const String searchResult = 'searchResult';
}
