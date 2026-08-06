/// A small expression parser and evaluator for JSON-like model values.
library simple_expressions;

import 'dart:collection';

typedef _EvaluatorFunction = _Value Function(Map? model);

/// The error raised when an expression cannot be parsed.
class ExpressionParseException extends FormatException {
  ExpressionParseException(String message, this.position)
      : super('Invalid Expression at $position: $message', null, position);

  /// Reports a failure that has no meaningful source position, matching the
  /// upstream `Invalid Expression: {message}` format.
  ExpressionParseException.withoutPosition(String message)
      : position = -1,
        super('Invalid Expression: $message');

  /// The zero-based source position of the failure, or `-1` when unknown.
  final int position;
}

/// A reusable parsed expression.
class Expression {
  Expression._compiled(this._evaluator);

  Expression(Object expression) {
    if (expression is bool) {
      _evaluator = _Compiled.constant(expression ? _trueValue : _falseValue);
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
  ///
  /// Arrays read from the model are returned as the model's live lists,
  /// not defensive copies.
  Object? evaluateValue(Object? model) =>
      _evaluator(model is Map ? model : null).toPublicValue();

  /// Evaluates the expression using JavaScript-like truthiness.
  bool evaluate(Object? model) =>
      _evaluator(model is Map ? model : null).isTruthy;
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
    final key = expression is String ? expression : '$expression';
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

  // Callers pass already-trimmed input.
  static _Compiled _getParsedExpression(String expression) {
    if (expression.isEmpty) {
      throw ExpressionParseException('formatting', 0);
    }
    if (_enabledCaches) {
      final cached = _parseCache[expression];
      if (cached != null) return cached;
    }

    final result = _ExpressionParser(expression).parse();
    if (_enabledCaches) _setCacheValue(_parseCache, expression, result);
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
      final code = source.codeUnitAt(index);
      if (code == 0x28 || // (
          code == 0x29 || // )
          code == 0x2c || // ,
          code == 0x5b || // [
          code == 0x5d || // ]
          code <= 32) {
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
        final segments = _validateReference(path);
        _tokenizer.next();
        if (segments.length == 1) {
          return _Compiled((model) => _resolveSingle(model, path));
        }
        return _Compiled((model) => _resolvePath(model, path, segments));
      case _TokenKind.identifier:
        final identifier = _tokenizer.value;
        _tokenizer.next();
        final normalized = identifier.toLowerCase();
        if (normalized == 'true') {
          return _Compiled.constant(_trueValue);
        }
        if (normalized == 'false') {
          return _Compiled.constant(_falseValue);
        }
        return _parseCall(identifier, normalized);
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
    final compiled = List<_Compiled>.of(values, growable: false);
    return _Compiled((model) {
      final items =
          List<_Value>.filled(compiled.length, const _Value.missing());
      for (var index = 0; index < compiled.length; index++) {
        items[index] = compiled[index](model);
      }
      return _Value.array(items);
    });
  }

  _Compiled _parseCall(String operator, String normalized) {
    if (_tokenizer.kind != _TokenKind.openParen) {
      _fail('invalid operator: $operator');
    }
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
        return _Compiled(
            (model) => inner(model).isTruthy ? _falseValue : _trueValue);
      case 'empty':
        return _Compiled(
            (model) => _isEmpty(inner(model)) ? _trueValue : _falseValue);
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
        return _Compiled(
            (model) => inner(model).isNullish ? _falseValue : _trueValue);
      default:
        _fail('invalid operator: $operator');
    }
  }

  _Compiled _compileBinary(String operator, _Compiled left, _Compiled right) {
    switch (operator) {
      case 'eq':
        return _Compiled((model) =>
            _looseEquals(left(model), right(model)) ? _trueValue : _falseValue);
      case 'contains':
        return _Compiled((model) =>
            _contains(left(model), right(model)) ? _trueValue : _falseValue);
      case 'startswith':
        return _Compiled((model) =>
            _startsWith(left(model), right(model)) ? _trueValue : _falseValue);
      case 'endswith':
        return _Compiled((model) =>
            _endsWith(left(model), right(model)) ? _trueValue : _falseValue);
      case 'in':
        return _Compiled((model) =>
            _inList(left(model), right(model)) ? _trueValue : _falseValue);
      case 'gt':
        return _Compiled((model) =>
            _compare(left(model), right(model)) > 0 ? _trueValue : _falseValue);
      case 'lt':
        return _Compiled((model) =>
            _compare(left(model), right(model)) < 0 ? _trueValue : _falseValue);
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
      return _Compiled((model) =>
          regex.hasMatch(_regexInput(value(model))) ? _trueValue : _falseValue);
    }
    return _Compiled((model) {
      final runtimePattern = pattern(model);
      if (runtimePattern.kind != _ValueKind.string ||
          !runtimePattern.isTruthy) {
        return _falseValue;
      }
      final regex = _runtimeRegExp(runtimePattern.value as String);
      return regex.hasMatch(_regexInput(value(model)))
          ? _trueValue
          : _falseValue;
    });
  }

  _Compiled _compileVariadic(String operator, List<_Compiled> values) {
    switch (operator) {
      case 'or':
        return _Compiled((model) {
          for (final value in values) {
            if (value(model).isTruthy) return _trueValue;
          }
          return _falseValue;
        });
      case 'and':
        return _Compiled((model) {
          for (final value in values) {
            if (!value(model).isTruthy) return _falseValue;
          }
          return _trueValue;
        });
      case 'concat':
        if (values.every((value) => value.constantValue != null)) {
          final buffer = StringBuffer();
          for (final value in values) {
            _writeConcatValue(buffer, value.constantValue!);
          }
          return _Compiled.constant(_Value.string(buffer.toString()));
        }
        return _Compiled((model) {
          final buffer = StringBuffer();
          for (final value in values) {
            _writeConcatValue(buffer, value(model));
          }
          return _Value.string(buffer.toString());
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

  static List<String> _validateReference(String path) {
    const unsafe = {'__proto__', 'constructor', 'prototype'};
    final segments = path.split('.');
    for (final segment in segments) {
      if (segment.isEmpty || unsafe.contains(segment)) {
        throw ExpressionParseException.withoutPosition(
            'invalid model reference: #$path');
      }
    }
    return segments;
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

  _Value call(Map? model) => function(model);
}

enum _ValueKind { missing, nullValue, boolean, number, string, array, object }

const _Value _trueValue = _Value.boolean(true);
const _Value _falseValue = _Value.boolean(false);
const _Value _zeroValue = _Value(_ValueKind.number, 0.0);

class _Value {
  const _Value(this.kind, this.value);

  const _Value.missing() : this(_ValueKind.missing, null);
  const _Value.nullValue() : this(_ValueKind.nullValue, null);
  const _Value.boolean(bool value) : this(_ValueKind.boolean, value);
  _Value.number(num value) : this(_ValueKind.number, value.toDouble());
  const _Value.string(String value) : this(_ValueKind.string, value);

  /// Arrays hold either the model's raw list (items converted lazily on
  /// access) or an already-converted `List<_Value>` for literal lists.
  const _Value.array(List value) : this(_ValueKind.array, value);
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
        final items = value as List;
        if (items is List<_Value>) {
          return items.map((item) => item.toPublicValue()).toList();
        }
        return items;
      case _ValueKind.object:
        return value;
    }
  }
}

_Value _resolveSingle(Map? model, String key) {
  if (model == null) return const _Value.missing();
  final value = model[key];
  if (value == null && !model.containsKey(key)) {
    return const _Value.missing();
  }
  return _fromPublic(value);
}

_Value _resolvePath(Map? model, String path, List<String> segments) {
  if (model == null) return const _Value.missing();
  // A member literally named the whole dotted path wins, matching upstream.
  final dotted = model[path];
  if (dotted != null || model.containsKey(path)) return _fromPublic(dotted);

  Object? current = model;
  for (final segment in segments) {
    if (current is! Map) return const _Value.missing();
    final next = current[segment];
    if (next == null && !current.containsKey(segment)) {
      return const _Value.missing();
    }
    current = next;
  }
  return _fromPublic(current);
}

_Value _fromPublic(Object? value) {
  if (value == null) return const _Value.nullValue();
  if (value is bool) return value ? _trueValue : _falseValue;
  if (value is num) return _Value.number(value);
  if (value is String) return _Value.string(value);
  if (value is List) return _Value.array(value);
  if (value is Map) return _Value.object(value.cast<Object?, Object?>());
  return _Value.object(<Object?, Object?>{});
}

/// Lifts one array item into the value model; literal-list items are already
/// `_Value`s, model-list items convert lazily here.
_Value _arrayItem(Object? item) => item is _Value ? item : _fromPublic(item);

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
  if (value.isNullish) return _zeroValue;
  if (value.kind == _ValueKind.string) {
    return _Value.number((value.value as String).length);
  }
  if (value.kind == _ValueKind.array) {
    return _Value.number((value.value as List).length);
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
  final items = list.value as List;
  for (var index = 0; index < items.length; index++) {
    if (_looseEquals(value, _arrayItem(items[index]))) return true;
  }
  return false;
}

void _writeConcatValue(StringBuffer buffer, _Value value) {
  if (value.isTruthy) buffer.write(_toJavaScriptString(value));
}

const int _maxStructuralDepth = 64;

const int _runtimePatternCacheLimit = 64;
final Map<String, RegExp> _runtimePatterns = <String, RegExp>{};

/// Compiles and caches a model-supplied `match()` pattern. Patterns come from
/// caller data, so the cache stays bounded: cleared wholesale when full.
RegExp _runtimeRegExp(String pattern) {
  final cached = _runtimePatterns[pattern];
  if (cached != null) return cached;
  final regex = RegExp(pattern);
  if (_runtimePatterns.length >= _runtimePatternCacheLimit) {
    _runtimePatterns.clear();
  }
  _runtimePatterns[pattern] = regex;
  return regex;
}

bool _looseEquals(_Value left, _Value right, [int depth = 0]) {
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
        return _structuralArrayEquals(left, right, depth);
      case _ValueKind.object:
        return _structuralObjectEquals(left, right, depth);
    }
  }
  if (left.isNullish && right.isNullish) return true;
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

bool _structuralArrayEquals(_Value left, _Value right, int depth) {
  final leftItems = left.value as List;
  final rightItems = right.value as List;
  if (identical(leftItems, rightItems)) return true;
  if (depth >= _maxStructuralDepth) return false;
  if (leftItems.length != rightItems.length) return false;
  for (var index = 0; index < leftItems.length; index++) {
    if (!_looseEquals(_arrayItem(leftItems[index]),
        _arrayItem(rightItems[index]), depth + 1)) {
      return false;
    }
  }
  return true;
}

bool _structuralObjectEquals(_Value left, _Value right, int depth) {
  final leftEntries = left.value as Map;
  final rightEntries = right.value as Map;
  if (identical(leftEntries, rightEntries)) return true;
  if (depth >= _maxStructuralDepth) return false;
  if (leftEntries.length != rightEntries.length) return false;
  for (final key in leftEntries.keys) {
    if (!rightEntries.containsKey(key)) return false;
    if (!_looseEquals(_fromPublic(leftEntries[key]),
        _fromPublic(rightEntries[key]), depth + 1)) {
      return false;
    }
  }
  return true;
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
      // A string converts only if it parses as a number; unlike JavaScript,
      // an empty string is not zero and `Infinity` is not a keyword.
      return double.tryParse((value.value as String).trim()) ?? double.nan;
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
      final items = value.value as List;
      final buffer = StringBuffer();
      for (var index = 0; index < items.length; index++) {
        if (index > 0) buffer.write(',');
        final item = _arrayItem(items[index]);
        if (!item.isNullish) buffer.write(_toJavaScriptString(item));
      }
      return buffer.toString();
    case _ValueKind.object:
      return '[object Object]';
  }
}

const int _plainNotationMinExponent = -6;
const int _plainNotationMaxExponent = 21;

/// Renders a double as its shortest round-trip decimal, using plain notation for
/// magnitudes in `[1e-6, 1e21)` and lowercase exponent notation outside that range.
String _formatNumber(double value) {
  if (value.isNaN) return 'NaN';
  if (value == double.infinity) return 'Infinity';
  if (value == double.negativeInfinity) return '-Infinity';
  if (value == 0) return '0';

  var text = value.toStringAsExponential();
  final negative = text.startsWith('-');
  if (negative) text = text.substring(1);

  final separator = text.indexOf('e');
  // toStringAsExponential normalises to a single leading digit, so the
  // exponent is already the decimal exponent of that digit.
  final exponent = int.parse(text.substring(separator + 1));
  final digits = text.substring(0, separator).replaceFirst('.', '');

  final formatted = exponent >= _plainNotationMinExponent &&
          exponent < _plainNotationMaxExponent
      ? _toPlainNotation(digits, exponent)
      : _toExponentNotation(digits, exponent);

  return negative ? '-$formatted' : formatted;
}

String _toPlainNotation(String digits, int exponent) {
  if (exponent < 0) {
    return '0.${'0' * (-exponent - 1)}$digits';
  }
  if (exponent >= digits.length - 1) {
    return digits + '0' * (exponent - digits.length + 1);
  }
  return '${digits.substring(0, exponent + 1)}.${digits.substring(exponent + 1)}';
}

String _toExponentNotation(String digits, int exponent) {
  final mantissa = digits.length == 1
      ? digits
      : '${digits.substring(0, 1)}.${digits.substring(1)}';
  return '${mantissa}e${exponent < 0 ? '-' : '+'}${exponent.abs()}';
}
