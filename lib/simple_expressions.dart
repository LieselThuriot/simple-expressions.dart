/// A small expression parser and evaluator for JSON-like model values.
library simple_expressions;

import 'dart:collection';

typedef _EvaluatorFunction = _Value Function(_ExpressionModel model);

/// The error raised when an expression cannot be parsed.
class ExpressionParseException extends FormatException {
  ExpressionParseException(String message, this.position)
      : super('Invalid Expression at $position: $message', null, position);

  final int position;
}

/// A reusable parsed expression.
class Expression {
  Expression._compiled(this._evaluator);

  Expression(Object expression) {
    if (expression is bool) {
      _evaluator = _Compiled.constant(_Value.boolean(expression));
    } else if (expression is String) {
      final normalized = expression.trim();
      if (normalized.isEmpty) {
        throw ExpressionParseException('whitespace', 0);
      }
      _evaluator = SimpleExpressions._getParsedExpression(normalized);
    } else {
      throw ArgumentError('Invalid Expression: unsupported type');
    }
  }

  late final _Compiled _evaluator;

  /// Evaluates the expression and returns its raw value.
  Object? evaluateValue(Object? model) =>
      _evaluator(_ExpressionModel(model)).toPublicValue();

  /// Evaluates the expression using JavaScript-like truthiness.
  bool evaluate(Object? model) => _evaluator(_ExpressionModel(model)).isTruthy;
}

/// Parses expression text into a reusable evaluator.
Expression parseExpression(String expression) => Expression._compiled(
    SimpleExpressions._getParsedExpression(expression.trim()));

/// Evaluates an expression and returns its truthiness.
bool executeExpression(Object? model, Object expression) =>
    SimpleExpressions.get(expression).evaluate(model);

/// Controls the evaluator caches and constructs reusable expressions.
class SimpleExpressions {
  SimpleExpressions._();

  static const int _defaultCacheLimit = 1000;
  static int _cacheLimit = _defaultCacheLimit;
  static bool _enabledCaches = true;
  static final LinkedHashMap<String, _Compiled> _parseCache = LinkedHashMap();
  static final LinkedHashMap<String, Expression> _expressionCache =
      LinkedHashMap();

  /// Returns a cached reusable expression when caching is enabled.
  static Expression get(Object expression) {
    final key = '$expression';
    if (_enabledCaches) {
      final cached = _expressionCache[key];
      if (cached != null) return cached;
    }

    final result = Expression(expression);
    if (_enabledCaches) _setCacheValue(_expressionCache, key, result);
    return result;
  }

  /// Clears parsed-expression and/or reusable-expression caches.
  static void clear({bool? parsed, bool? expression}) {
    if (parsed == null && expression == null) {
      _parseCache.clear();
      _expressionCache.clear();
      return;
    }
    if (parsed == true) _parseCache.clear();
    if (expression == true) _expressionCache.clear();
  }

  /// Disables caching and clears existing entries.
  static void disableCaches() {
    _enabledCaches = false;
    clear();
  }

  /// Enables caching without changing the configured cache limit.
  static void enableCaches() {
    _enabledCaches = true;
  }

  /// Sets the positive FIFO cache limit. Non-positive values disable caching.
  static void setCacheLimit(int limit) {
    if (limit <= 0) {
      disableCaches();
      return;
    }
    _cacheLimit = limit;
    _trimCache(_parseCache);
    _trimCache(_expressionCache);
  }

  static _Compiled _getParsedExpression(String expression) {
    final normalized = expression.trim();
    if (normalized.isEmpty) {
      throw ExpressionParseException('formatting', 0);
    }
    if (_enabledCaches) {
      final cached = _parseCache[normalized];
      if (cached != null) return cached;
    }

    final result = _ExpressionParser(normalized).parse();
    if (_enabledCaches) _setCacheValue(_parseCache, normalized, result);
    return result;
  }

  static void _setCacheValue<T>(
      LinkedHashMap<String, T> cache, String key, T value) {
    if (cache.length >= _cacheLimit) cache.remove(cache.keys.first);
    cache[key] = value;
  }

  static void _trimCache<T>(LinkedHashMap<String, T> cache) {
    while (cache.length > _cacheLimit) {
      cache.remove(cache.keys.first);
    }
  }
}

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
    while (index < source.length && source.codeUnitAt(index) <= 32) index++;
    if (index >= source.length) {
      current = _Token(_TokenKind.end, '', index);
      return;
    }

    final start = index;
    final character = source[index];
    switch (character) {
      case '(':
        index++;
        current = _Token(_TokenKind.openParen, character, index);
        return;
      case ')':
        index++;
        current = _Token(_TokenKind.closeParen, character, index);
        return;
      case ',':
        index++;
        current = _Token(_TokenKind.comma, character, index);
        return;
      case '[':
        index++;
        current = _Token(_TokenKind.openBracket, character, index);
        return;
      case ']':
        index++;
        current = _Token(_TokenKind.closeBracket, character, index);
        return;
      case '#':
        index++;
        _readDelimitedToken();
        if (index == start + 1) _fail('missing model reference');
        current = _Token(
          _TokenKind.reference,
          source.substring(start + 1, index),
          index,
        );
        return;
      case '`':
      case '"':
      case "'":
        _readString(character);
        return;
    }

    if (_isIdentifierStart(character)) {
      index++;
      while (index < source.length && _isIdentifierPart(source[index])) index++;
      current =
          _Token(_TokenKind.identifier, source.substring(start, index), index);
      return;
    }

    _readDelimitedToken();
    final value = source.substring(start, index);
    if (_numericPattern.hasMatch(value)) {
      current = _Token(_TokenKind.number, value, index);
      return;
    }
    _fail('unexpected token $value');
  }

  static final RegExp _numericPattern = RegExp(
    r'^[+-]?(?:\d+(?:\.\d*)?|\.\d+)(?:[eE][+-]?\d+)?$',
  );

  void _readDelimitedToken() {
    while (index < source.length) {
      final character = source[index];
      if (character == '(' ||
          character == ')' ||
          character == ',' ||
          character == '[' ||
          character == ']' ||
          source.codeUnitAt(index) <= 32) {
        return;
      }
      index++;
    }
  }

  void _readString(String quote) {
    final start = index + 1;
    index++;
    var backslashCount = 0;
    while (index < source.length) {
      final character = source[index];
      if (character == '\\') {
        backslashCount++;
        index++;
        continue;
      }
      if (character == quote && backslashCount.isEven) {
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

  static bool _isIdentifierStart(String character) {
    final code = character.codeUnitAt(0);
    return code >= 65 && code <= 90 || code >= 97 && code <= 122;
  }

  static bool _isIdentifierPart(String character) =>
      _isIdentifierStart(character);

  Never _fail(String message) => throw ExpressionParseException(message, index);
}

class _ExpressionParser {
  _ExpressionParser(String expression) : _tokenizer = _Tokenizer(expression);

  final _Tokenizer _tokenizer;

  _Compiled parse() {
    final result = _parseValue();
    if (_tokenizer.kind != _TokenKind.end) _fail('unexpected trailing input');
    return result;
  }

  _Compiled _parseValue() {
    switch (_tokenizer.kind) {
      case _TokenKind.string:
        final value = _tokenizer.value;
        _tokenizer.next();
        return _Compiled.constant(_Value.string(value));
      case _TokenKind.number:
        final value = double.parse(_tokenizer.value);
        _tokenizer.next();
        return _Compiled.constant(_Value.number(value));
      case _TokenKind.reference:
        final path = _tokenizer.value;
        _validateReference(path);
        _tokenizer.next();
        return _Compiled((_ExpressionModel model) => model.resolve(path));
      case _TokenKind.identifier:
        final identifier = _tokenizer.value;
        _tokenizer.next();
        if (identifier.toLowerCase() == 'true') {
          return _Compiled.constant(_Value.boolean(true));
        }
        if (identifier.toLowerCase() == 'false') {
          return _Compiled.constant(_Value.boolean(false));
        }
        return _parseCall(identifier);
      case _TokenKind.openBracket:
        return _parseList();
      default:
        _fail('expected an expression');
    }
  }

  _Compiled _parseList() {
    _tokenizer.next();
    if (_tokenizer.kind == _TokenKind.closeBracket) {
      _tokenizer.next();
      return _Compiled.constant(_Value.array(const <_Value>[]));
    }

    final values = <_Compiled>[_parseValue()];
    while (_tokenizer.kind == _TokenKind.comma) {
      _tokenizer.next();
      values.add(_parseValue());
    }
    if (_tokenizer.kind != _TokenKind.closeBracket) {
      _fail('expected closing bracket');
    }
    _tokenizer.next();
    return _Compiled(
        (model) => _Value.array(values.map((value) => value(model)).toList()));
  }

  _Compiled _parseCall(String operator) {
    if (_tokenizer.kind != _TokenKind.openParen) {
      _fail('invalid operator: $operator');
    }
    final normalized = operator.toLowerCase();
    final arity = _operatorArity(normalized);
    _tokenizer.next();
    if (_tokenizer.kind == _TokenKind.closeParen) {
      _fail('missing operator argument');
    }

    final left = _parseValue();
    if (arity == -1) {
      if (_tokenizer.kind != _TokenKind.comma) {
        _fail('operator $operator expects at least two arguments');
      }
      final values = <_Compiled>[left];
      while (_tokenizer.kind == _TokenKind.comma) {
        _tokenizer.next();
        values.add(_parseValue());
      }
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects at least two arguments');
      }
      _tokenizer.next();
      return _compileVariadic(normalized, values);
    }

    if (arity == 1) {
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects one argument');
      }
      _tokenizer.next();
      return _compileUnary(normalized, left);
    }

    if (_tokenizer.kind != _TokenKind.comma) {
      _fail(
          'operator $operator expects ${arity == 2 ? 'two' : 'three'} arguments');
    }
    _tokenizer.next();
    final right = _parseValue();
    if (arity == 2) {
      if (_tokenizer.kind != _TokenKind.closeParen) {
        _fail('operator $operator expects two arguments');
      }
      _tokenizer.next();
      return _compileBinary(normalized, left, right);
    }

    if (_tokenizer.kind != _TokenKind.comma) {
      _fail('operator $operator expects three arguments');
    }
    _tokenizer.next();
    final whenFalse = _parseValue();
    if (_tokenizer.kind != _TokenKind.closeParen) {
      _fail('operator $operator expects three arguments');
    }
    _tokenizer.next();
    return _compileTernary(normalized, left, right, whenFalse);
  }

  int _operatorArity(String operator) {
    switch (operator) {
      case 'not':
      case 'empty':
      case 'len':
      case 'lower':
      case 'upper':
      case 'trim':
      case 'defined':
        return 1;
      case 'eq':
      case 'contains':
      case 'startswith':
      case 'endswith':
      case 'gt':
      case 'lt':
      case 'match':
      case 'in':
        return 2;
      case 'or':
      case 'and':
      case 'concat':
        return -1;
      case 'if':
        return 3;
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileUnary(String operator, _Compiled inner) {
    switch (operator) {
      case 'not':
        return _Compiled((model) => _Value.boolean(!inner(model).isTruthy));
      case 'empty':
        return _Compiled((model) => _Value.boolean(_isEmpty(inner(model))));
      case 'len':
        return _Compiled((model) => _length(inner(model)));
      case 'lower':
        return _Compiled(
            (model) => _Value.string(_falsyString(inner(model)).toLowerCase()));
      case 'upper':
        return _Compiled(
            (model) => _Value.string(_falsyString(inner(model)).toUpperCase()));
      case 'trim':
        return _Compiled((model) => _trim(inner(model)));
      case 'defined':
        return _Compiled((model) => _Value.boolean(!inner(model).isNullish));
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileBinary(String operator, _Compiled left, _Compiled right) {
    switch (operator) {
      case 'eq':
        return _Compiled(
            (model) => _Value.boolean(_looseEquals(left(model), right(model))));
      case 'contains':
        return _Compiled(
            (model) => _Value.boolean(_contains(left(model), right(model))));
      case 'startswith':
        return _Compiled(
            (model) => _Value.boolean(_startsWith(left(model), right(model))));
      case 'endswith':
        return _Compiled(
            (model) => _Value.boolean(_endsWith(left(model), right(model))));
      case 'in':
        return _Compiled(
            (model) => _Value.boolean(_inList(left(model), right(model))));
      case 'gt':
        return _Compiled(
            (model) => _Value.boolean(_compare(left(model), right(model)) > 0));
      case 'lt':
        return _Compiled(
            (model) => _Value.boolean(_compare(left(model), right(model)) < 0));
      case 'match':
        return _compileMatch(left, right);
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileMatch(_Compiled value, _Compiled pattern) {
    final constant = pattern.constantValue;
    if (constant != null &&
        constant.kind == _ValueKind.string &&
        constant.isTruthy) {
      final regex = RegExp(constant.value as String);
      return _Compiled(
          (model) => _Value.boolean(regex.hasMatch(_regexInput(value(model)))));
    }
    return _Compiled((model) {
      final runtimePattern = pattern(model);
      if (runtimePattern.kind != _ValueKind.string ||
          !runtimePattern.isTruthy) {
        return _Value.boolean(false);
      }
      final regex = RegExp(runtimePattern.value as String);
      return _Value.boolean(regex.hasMatch(_regexInput(value(model))));
    });
  }

  _Compiled _compileVariadic(String operator, List<_Compiled> values) {
    switch (operator) {
      case 'or':
        return _Compiled((model) {
          for (final value in values) {
            if (value(model).isTruthy) return _Value.boolean(true);
          }
          return _Value.boolean(false);
        });
      case 'and':
        return _Compiled((model) {
          for (final value in values) {
            if (!value(model).isTruthy) return _Value.boolean(false);
          }
          return _Value.boolean(true);
        });
      case 'concat':
        if (values.every((value) => value.constantValue != null)) {
          var result = '';
          for (final value in values) {
            result = _concatValue(_Value.string(result), value.constantValue!);
          }
          return _Compiled.constant(_Value.string(result));
        }
        return _Compiled((model) {
          var result = '';
          for (final value in values) {
            result = _concatValue(_Value.string(result), value(model));
          }
          return _Value.string(result);
        });
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileTernary(
    String operator,
    _Compiled condition,
    _Compiled whenTrue,
    _Compiled whenFalse,
  ) {
    switch (operator) {
      case 'if':
        return _Compiled((model) =>
            condition(model).isTruthy ? whenTrue(model) : whenFalse(model));
      default:
        _fail('invalid operator: $operator');
    }
  }

  static void _validateReference(String path) {
    const unsafe = {'__proto__', 'constructor', 'prototype'};
    for (final segment in path.split('.')) {
      if (segment.isEmpty || unsafe.contains(segment)) {
        throw ExpressionParseException('invalid model reference: #$path', 0);
      }
    }
  }

  Never _fail(String message) =>
      throw ExpressionParseException(message, _tokenizer.position);
}

class _Compiled {
  _Compiled(this.function) : constantValue = null;

  _Compiled.constant(_Value value)
      : function = ((_) => value),
        constantValue = value;

  final _EvaluatorFunction function;
  final _Value? constantValue;

  _Value call(_ExpressionModel model) => function(model);
}

enum _ValueKind { missing, nullValue, boolean, number, string, array, object }

class _Value {
  const _Value(this.kind, this.value);

  const _Value.missing() : this(_ValueKind.missing, null);
  const _Value.nullValue() : this(_ValueKind.nullValue, null);
  const _Value.boolean(bool value) : this(_ValueKind.boolean, value);
  _Value.number(num value) : this(_ValueKind.number, value.toDouble());
  const _Value.string(String value) : this(_ValueKind.string, value);
  const _Value.array(List<_Value> value) : this(_ValueKind.array, value);
  const _Value.object(Map<Object?, Object?> value)
      : this(_ValueKind.object, value);

  final _ValueKind kind;
  final Object? value;

  bool get isNullish =>
      kind == _ValueKind.missing || kind == _ValueKind.nullValue;

  bool get isTruthy {
    switch (kind) {
      case _ValueKind.missing:
      case _ValueKind.nullValue:
        return false;
      case _ValueKind.boolean:
        return value as bool;
      case _ValueKind.number:
        final number = value as double;
        return number != 0 && !number.isNaN;
      case _ValueKind.string:
        return (value as String).isNotEmpty;
      case _ValueKind.array:
      case _ValueKind.object:
        return true;
    }
  }

  Object? toPublicValue() {
    switch (kind) {
      case _ValueKind.missing:
      case _ValueKind.nullValue:
        return null;
      case _ValueKind.boolean:
      case _ValueKind.number:
      case _ValueKind.string:
        return value;
      case _ValueKind.array:
        return (value as List<_Value>)
            .map((item) => item.toPublicValue())
            .toList();
      case _ValueKind.object:
        return value;
    }
  }
}

class _ExpressionModel {
  _ExpressionModel(Object? model) : root = model is Map ? model : null;

  final Map? root;

  _Value resolve(String path) {
    final model = root;
    if (model == null) return const _Value.missing();
    final segments = path.split('.');
    if (segments.length == 1) {
      return model.containsKey(path)
          ? _fromPublic(model[path])
          : const _Value.missing();
    }
    if (model.containsKey(path)) return _fromPublic(model[path]);

    Object? current = model;
    for (final segment in segments) {
      if (current is! Map || !current.containsKey(segment)) {
        return const _Value.missing();
      }
      current = current[segment];
    }
    return _fromPublic(current);
  }
}

_Value _fromPublic(Object? value) {
  if (value == null) return const _Value.nullValue();
  if (value is bool) return _Value.boolean(value);
  if (value is num) return _Value.number(value);
  if (value is String) return _Value.string(value);
  if (value is List) {
    return _Value.array(value.map(_fromPublic).toList());
  }
  if (value is Map) return _Value.object(value.cast<Object?, Object?>());
  return _Value.object(<Object?, Object?>{});
}

bool _isEmpty(_Value value) =>
    value.isNullish ||
    value.kind == _ValueKind.string && (value.value as String).isEmpty;

String _regexInput(_Value value) =>
    value.isTruthy ? _toJavaScriptString(value) : '';

String _falsyString(_Value value) => _regexInput(value);

_Value _trim(_Value value) {
  if (value.isNullish) return value;
  return _Value.string(_falsyString(value).trim());
}

_Value _length(_Value value) {
  if (value.isNullish) return _Value.number(0);
  if (value.kind == _ValueKind.string) {
    return _Value.number((value.value as String).length);
  }
  if (value.kind == _ValueKind.array) {
    return _Value.number((value.value as List<_Value>).length);
  }
  if (value.kind == _ValueKind.object) {
    final object = value.value as Map;
    if (object.containsKey('length')) return _fromPublic(object['length']);
  }
  throw StateError('Input does not have a length');
}

bool _contains(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).contains(_toJavaScriptString(right));

bool _startsWith(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).startsWith(_toJavaScriptString(right));

bool _endsWith(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).endsWith(_toJavaScriptString(right));

bool _inList(_Value value, _Value list) {
  if (list.kind != _ValueKind.array) return false;
  return (list.value as List<_Value>).any((item) => _looseEquals(value, item));
}

String _concatValue(_Value current, _Value value) =>
    (current.value as String) +
    (value.isTruthy ? _toJavaScriptString(value) : '');

bool _looseEquals(_Value left, _Value right) {
  if (left.kind == right.kind) {
    switch (left.kind) {
      case _ValueKind.missing:
      case _ValueKind.nullValue:
        return true;
      case _ValueKind.boolean:
        return left.value == right.value;
      case _ValueKind.number:
        return left.value == right.value;
      case _ValueKind.string:
        return left.value == right.value;
      case _ValueKind.array:
      case _ValueKind.object:
        return identical(left.value, right.value);
    }
  }
  if (left.isNullish || right.isNullish) return false;
  if (left.kind == _ValueKind.array || left.kind == _ValueKind.object) {
    return _looseEquals(_Value.string(_toJavaScriptString(left)), right);
  }
  if (right.kind == _ValueKind.array || right.kind == _ValueKind.object) {
    return _looseEquals(left, _Value.string(_toJavaScriptString(right)));
  }
  if (left.kind == _ValueKind.boolean ||
      right.kind == _ValueKind.boolean ||
      left.kind == _ValueKind.number && right.kind == _ValueKind.string ||
      left.kind == _ValueKind.string && right.kind == _ValueKind.number) {
    return _toNumber(left) == _toNumber(right);
  }
  return false;
}

int _compare(_Value left, _Value right) {
  if (left.kind == _ValueKind.array || left.kind == _ValueKind.object) {
    left = _Value.string(_toJavaScriptString(left));
  }
  if (right.kind == _ValueKind.array || right.kind == _ValueKind.object) {
    right = _Value.string(_toJavaScriptString(right));
  }
  if (left.kind == _ValueKind.string && right.kind == _ValueKind.string) {
    return (left.value as String).compareTo(right.value as String);
  }
  final leftNumber = _toNumber(left);
  final rightNumber = _toNumber(right);
  if (leftNumber.isNaN || rightNumber.isNaN) return 0;
  return leftNumber.compareTo(rightNumber);
}

double _toNumber(_Value value) {
  switch (value.kind) {
    case _ValueKind.nullValue:
      return 0;
    case _ValueKind.boolean:
      return value.value as bool ? 1 : 0;
    case _ValueKind.number:
      return value.value as double;
    case _ValueKind.string:
      final text = (value.value as String).trim();
      if (text.isEmpty) return 0;
      if (text == 'Infinity' || text == '+Infinity') return double.infinity;
      if (text == '-Infinity') return double.negativeInfinity;
      return double.tryParse(text) ?? double.nan;
    default:
      return double.nan;
  }
}

String _toJavaScriptString(_Value value) {
  switch (value.kind) {
    case _ValueKind.missing:
      return 'undefined';
    case _ValueKind.nullValue:
      return 'null';
    case _ValueKind.boolean:
      return value.value as bool ? 'true' : 'false';
    case _ValueKind.number:
      return _formatNumber(value.value as double);
    case _ValueKind.string:
      return value.value as String;
    case _ValueKind.array:
      return (value.value as List<_Value>)
          .map((item) => item.isNullish ? '' : _toJavaScriptString(item))
          .join(',');
    case _ValueKind.object:
      return '[object Object]';
  }
}

String _formatNumber(double value) {
  if (value.isNaN) return 'NaN';
  if (value == double.infinity) return 'Infinity';
  if (value == double.negativeInfinity) return '-Infinity';
  if (value == 0) return '0';
  if (value == value.roundToDouble()) return value.toInt().toString();
  return value.toString();
}
