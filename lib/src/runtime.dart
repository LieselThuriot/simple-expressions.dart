part of 'simple_expressions_impl.dart';

double _truncate(double value) => value.truncateToDouble();

double _floor(double value) => value.floorToDouble();

double _ceil(double value) => value.ceilToDouble();

double _mathNumber(_Value value, {bool strict = false}) {
  if (value.kind == _ValueKind.string &&
      (value.value as String).trim().isEmpty) {
    if (strict) throw StateError('Invalid numeric value');
    return 0;
  }
  return _toNumber(value, strict: strict);
}

double _num(_Value value) {
  return _mathNumber(value, strict: true);
}

double _javascriptRemainder(double dividend, double divisor) {
  if (divisor == 0) throw StateError('Division by zero');
  if (dividend.isNaN || divisor.isNaN || dividend.isInfinite) {
    return double.nan;
  }
  if (divisor.isInfinite || dividend == 0) return dividend;
  return dividend.remainder(divisor);
}

double _javascriptMin(double left, double right) {
  if (left.isNaN || right.isNaN) return double.nan;
  if (left == 0 && right == 0) {
    return left.isNegative || right.isNegative ? -0.0 : 0.0;
  }
  return left < right ? left : right;
}

double _javascriptMax(double left, double right) {
  if (left.isNaN || right.isNaN) return double.nan;
  if (left == 0 && right == 0) {
    return left.isNegative && right.isNegative ? -0.0 : 0.0;
  }
  return left > right ? left : right;
}

_Value _round(_Value value, _Value decimals) {
  final places = _mathNumber(decimals, strict: true);
  if (places.isNaN ||
      places.isInfinite ||
      places != places.truncateToDouble() ||
      places < 0 ||
      places > 9007199254740991) {
    throw StateError('Round precision must be a non-negative safe integer');
  }
  final factor = math.pow(10, places).toDouble();
  if (factor.isInfinite) {
    throw StateError('Round precision is too large');
  }
  final number = _mathNumber(value, strict: true);
  final result = (number * factor + 0.5).floorToDouble() / factor;
  return _Value.number(result == 0 && number.isNegative ? -0.0 : result);
}

class _Compiled {
  _Compiled(this.function) : constantValue = null;

  _Compiled.constant(_Value value)
      : function = ((_) => value),
        constantValue = value;

  final _EvaluatorFunction function;
  final _Value? constantValue;

  _Value call(Object? model) => function(model);
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
  const _Value.object(Map value) : this(_ValueKind.object, value);

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

_Value _resolveSingle(Object? model, String key) {
  if (model is! Map) return const _Value.missing();
  final value = model[key];
  if (value == null && !model.containsKey(key)) {
    return const _Value.missing();
  }
  return _fromPublic(value);
}

_Value _resolvePath(Object? model, String path, List<String> segments) {
  if (model is! Map) return const _Value.missing();
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
  if (value is Map) return _Value.object(value);
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

double _toNumber(_Value value, {bool strict = false}) {
  if (strict) {
    if (value.kind == _ValueKind.number) {
      final number = value.value as double;
      if (number.isFinite) return number;
    } else if (value.kind == _ValueKind.string) {
      final text = (value.value as String).trim();
      final number = _parseJavaScriptNumber(text);
      if (text.isNotEmpty && number != null && number.isFinite) return number;
    }
    throw StateError('Invalid numeric value');
  }

  switch (value.kind) {
    case _ValueKind.nullValue:
      return 0;
    case _ValueKind.boolean:
      return value.value as bool ? 1 : 0;
    case _ValueKind.number:
      return value.value as double;
    case _ValueKind.string:
      final text = (value.value as String).trim();
      final number = _parseJavaScriptNumber(text);
      return number ?? double.nan;
    default:
      return double.nan;
  }
}

double? _parseJavaScriptNumber(String text) {
  if (text.length > 2 && text.startsWith('0')) {
    final radix = switch (text[1]) {
      'x' || 'X' => 16,
      'b' || 'B' => 2,
      'o' || 'O' => 8,
      _ => null,
    };
    if (radix != null) {
      return BigInt.tryParse(text.substring(2), radix: radix)?.toDouble();
    }
  }
  return double.tryParse(text);
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
