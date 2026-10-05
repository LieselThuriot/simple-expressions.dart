part of 'simple_expressions_impl.dart';

enum _TokenKind {
  end,
  identifier,
  number,
  string,
  reference,
  openParen,
  closeParen,
  comma,
  openBracket,
  closeBracket,
}

class _Token {
  const _Token(this.kind, this.value, this.position);

  final _TokenKind kind;
  final String value;
  final int position;
}

class _Tokenizer {
  _Tokenizer(this.source) {
    next();
  }

  final String source;
  int index = 0;
  late _Token current;

  _TokenKind get kind => current.kind;
  String get value => current.value;
  int get position => index;

  void next() {
    while (index < source.length &&
        _isPortableWhitespace(source.codeUnitAt(index))) {
      index++;
    }
    if (index >= source.length) {
      current = _Token(_TokenKind.end, '', index);
      return;
    }

    final start = index;
    final code = source.codeUnitAt(index);
    switch (code) {
      case 0x28: // (
        index++;
        current = _Token(_TokenKind.openParen, '(', index);
        return;
      case 0x29: // )
        index++;
        current = _Token(_TokenKind.closeParen, ')', index);
        return;
      case 0x2c: // ,
        index++;
        current = _Token(_TokenKind.comma, ',', index);
        return;
      case 0x5b: // [
        index++;
        current = _Token(_TokenKind.openBracket, '[', index);
        return;
      case 0x5d: // ]
        index++;
        current = _Token(_TokenKind.closeBracket, ']', index);
        return;
      case 0x23: // #
        index++;
        _readDelimitedToken();
        if (index == start + 1) _fail('missing model reference');
        current = _Token(
          _TokenKind.reference,
          source.substring(start + 1, index),
          index,
        );
        return;
      case 0x60: // `
      case 0x22: // "
      case 0x27: // '
        _readString(code);
        return;
    }

    if (_isIdentifierCode(code)) {
      index++;
      while (index < source.length &&
          _isIdentifierCode(source.codeUnitAt(index))) {
        index++;
      }
      current =
          _Token(_TokenKind.identifier, source.substring(start, index), index);
      return;
    }

    _readDelimitedToken();
    final value = source.substring(start, index);
    if (_decimalPattern.hasMatch(value)) {
      current = _Token(_TokenKind.number, value, index);
      return;
    }
    _fail('unexpected token $value');
  }

  void _readDelimitedToken() {
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code == 0x28 || // (
          code == 0x29 || // )
          code == 0x2c || // ,
          code == 0x5b || // [
          code == 0x5d || // ]
          _isPortableWhitespace(code)) {
        return;
      }
      index++;
    }
  }

  void _readString(int quote) {
    final start = index + 1;
    index++;
    var backslashCount = 0;
    while (index < source.length) {
      final code = source.codeUnitAt(index);
      if (code == 0x5c) {
        // backslash
        backslashCount++;
        index++;
        continue;
      }
      if (code == quote && backslashCount.isEven) {
        current = _Token(
            _TokenKind.string, source.substring(start, index), index + 1);
        index++;
        return;
      }
      backslashCount = 0;
      index++;
    }
    _fail('unterminated string');
  }

  static bool _isIdentifierCode(int code) =>
      code >= 65 && code <= 90 || code >= 97 && code <= 122;

  Never _fail(String message) => throw ExpressionParseException(message, index);
}
