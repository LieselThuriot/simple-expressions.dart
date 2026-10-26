part of 'simple_expressions_impl.dart';

final RegExp _decimalPattern = RegExp(
  r'^[+-]?(?:[0-9]+(?:\.[0-9]*)?|\.[0-9]+)(?:[eE][+-]?[0-9]+)?$',
);

bool _isPortableWhitespace(int code) =>
    code >= 0x0009 && code <= 0x000d ||
    code == 0x0020 ||
    code == 0x0085 ||
    code == 0x00a0 ||
    code == 0x1680 ||
    code >= 0x2000 && code <= 0x200a ||
    code == 0x2028 ||
    code == 0x2029 ||
    code == 0x202f ||
    code == 0x205f ||
    code == 0x3000;

String _trimPortableWhitespace(String value) {
  var start = 0;
  var end = value.length;
  while (start < end && _isPortableWhitespace(value.codeUnitAt(start))) {
    start++;
  }
  while (end > start && _isPortableWhitespace(value.codeUnitAt(end - 1))) {
    end--;
  }
  return start == 0 && end == value.length
      ? value
      : value.substring(start, end);
}

_Value _numericResult(num value) {
  final result = value.toDouble();
  if (!result.isFinite) {
    throw ExpressionEvaluationException('Invalid numeric result');
  }
  return _Value.number(result);
}

double _signedRemainder(double dividend, double divisor) {
  if (divisor == 0) throw ExpressionEvaluationException('Division by zero');
  if (dividend == 0) return dividend;
  return dividend.remainder(divisor);
}

_Value _round(_Value value, _Value decimals) {
  final placesValue = _toNumber(decimals);
  if (placesValue != placesValue.truncateToDouble() || placesValue < 0) {
    throw ExpressionEvaluationException(
        'Round precision must be a non-negative safe integer');
  }
  if (placesValue > 308) {
    throw ExpressionEvaluationException('Round precision is too large');
  }
  final number = _toNumber(value);
  final places = placesValue.toInt();
  if (number == 0) return _zeroValue;

  final data = ByteData(8)..setFloat64(0, number.abs(), Endian.big);
  // The JavaScript backend supports 32-bit accessors, but not getUint64.
  final high = data.getUint32(0, Endian.big);
  final low = data.getUint32(4, Endian.big);
  final exponentBits = (high >> 20) & 0x7ff;
  final fraction = (BigInt.from(high & 0xfffff) << 32) | BigInt.from(low);
  final significand =
      exponentBits == 0 ? fraction : (BigInt.one << 52) | fraction;
  final binaryExponent = exponentBits == 0 ? -1074 : exponentBits - 1023 - 52;
  final numerator = significand * BigInt.from(5).pow(places);
  final shift = binaryExponent + places;
  BigInt rounded;
  if (shift >= 0) {
    rounded = numerator << shift;
  } else {
    final divisor = BigInt.one << -shift;
    final quotient = numerator ~/ divisor;
    final remainder = numerator.remainder(divisor);
    rounded = remainder * BigInt.from(2) >= divisor
        ? quotient + BigInt.one
        : quotient;
  }
  if (number.isNegative) rounded = -rounded;

  final result =
      places == 0 ? rounded.toDouble() : double.parse('${rounded}e-$places');
  return _numericResult(result);
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
  // Scalar numbers are normalized; raw numbers nested in live lists/maps are
  // returned without walking or copying those containers.
  _Value.number(num value)
      : this(_ValueKind.number, value == 0 ? 0.0 : value.toDouble());
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

String _falsyText(_Value value) => value.isTruthy ? _textValue(value) : '';

_Value _trim(_Value value) {
  if (value.isNullish) return value;
  return _Value.string(_trimPortableWhitespace(_falsyText(value)));
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
  throw ExpressionEvaluationException('Input does not have a length');
}

bool _contains(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).contains(_textValue(right));

bool _startsWith(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).startsWith(_textValue(right));

bool _endsWith(_Value left, _Value right) =>
    left.kind == _ValueKind.string &&
    (left.value as String).endsWith(_textValue(right));

bool _inList(_Value value, _Value list) {
  if (list.kind != _ValueKind.array) return false;
  final items = list.value as List;
  for (var index = 0; index < items.length; index++) {
    if (_looseEquals(value, _arrayItem(items[index]))) return true;
  }
  return false;
}

void _writeConcatValue(StringBuffer buffer, _Value value) {
  if (value.isTruthy) buffer.write(_textValue(value));
}

double _toNumber(_Value value) {
  if (value.kind == _ValueKind.number) {
    final number = value.value as double;
    if (number.isFinite) return number;
  } else if (value.kind == _ValueKind.string) {
    final number = _parseDecimalNumber(value.value as String);
    if (number != null) return number;
  }
  throw ExpressionEvaluationException('Invalid numeric value');
}

double? _parseDecimalNumber(String value) {
  final text = _trimPortableWhitespace(value);
  if (!_decimalPattern.hasMatch(text)) return null;
  final parsed = _parseDecimalLiteral(text);
  return parsed.isFinite ? parsed : null;
}

double _parseDecimalLiteral(String text) {
  final parsed = double.tryParse(text);
  if (parsed != null) return parsed;
  // Some Dart versions do not accept the literal grammar's trailing dot.
  final dot = text.indexOf('.');
  if (dot > 0 &&
      (dot + 1 == text.length ||
          text[dot + 1] == 'e' ||
          text[dot + 1] == 'E')) {
    return double.parse(text.substring(0, dot) + text.substring(dot + 1));
  }
  return double.parse(text);
}

String _textValue(_Value value, [Set<List>? activeLists]) {
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
      activeLists ??= HashSet<List>.identity();
      if (!activeLists.add(items)) {
        throw ExpressionEvaluationException('Cyclic list value');
      }
      try {
        final buffer = StringBuffer();
        for (var index = 0; index < items.length; index++) {
          if (index > 0) buffer.write(',');
          final item = _arrayItem(items[index]);
          if (!item.isNullish) {
            buffer.write(_textValue(item, activeLists));
          }
        }
        return buffer.toString();
      } finally {
        activeLists.remove(items);
      }
    case _ValueKind.object:
      return '[object Object]';
  }
}
