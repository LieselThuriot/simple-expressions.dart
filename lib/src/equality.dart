part of 'simple_expressions_impl.dart';

class _EqualityContext {
  final List<(Object, Object)> pairs = [];

  bool contains(Object left, Object right) => pairs
      .any((pair) => identical(pair.$1, left) && identical(pair.$2, right));
}

bool _looseEquals(_Value left, _Value right, [_EqualityContext? context]) {
  context ??= _EqualityContext();
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
        return _structuralArrayEquals(left, right, context);
      case _ValueKind.object:
        return _structuralObjectEquals(left, right, context);
    }
  }
  if (left.isNullish && right.isNullish) return true;
  if (left.isNullish || right.isNullish) return false;
  if (_isCollection(left) || _isCollection(right)) return false;

  final leftNumber = _equalityNumber(left);
  final rightNumber = _equalityNumber(right);
  if (leftNumber != null && rightNumber != null) {
    return leftNumber == rightNumber;
  }
  return false;
}

bool _isCollection(_Value value) =>
    value.kind == _ValueKind.array || value.kind == _ValueKind.object;

double? _equalityNumber(_Value value) {
  switch (value.kind) {
    case _ValueKind.boolean:
      return value.value as bool ? 1 : 0;
    case _ValueKind.number:
      final number = value.value as double;
      return number.isFinite ? number : null;
    case _ValueKind.string:
      return _parseDecimalNumber(value.value as String);
    default:
      return null;
  }
}

bool _structuralArrayEquals(
    _Value left, _Value right, _EqualityContext context) {
  final leftItems = left.value as List;
  final rightItems = right.value as List;
  if (identical(leftItems, rightItems)) return true;
  if (context.contains(leftItems, rightItems)) return true;
  context.pairs.add((leftItems, rightItems));
  if (leftItems.length != rightItems.length) return false;
  for (var index = 0; index < leftItems.length; index++) {
    if (!_looseEquals(
        _arrayItem(leftItems[index]), _arrayItem(rightItems[index]), context)) {
      return false;
    }
  }
  return true;
}

bool _structuralObjectEquals(
    _Value left, _Value right, _EqualityContext context) {
  final leftEntries = left.value as Map;
  final rightEntries = right.value as Map;
  if (identical(leftEntries, rightEntries)) return true;
  if (context.contains(leftEntries, rightEntries)) return true;
  context.pairs.add((leftEntries, rightEntries));
  if (leftEntries.length != rightEntries.length) return false;
  for (final key in leftEntries.keys) {
    if (!rightEntries.containsKey(key)) return false;
    if (!_looseEquals(_fromPublic(leftEntries[key]),
        _fromPublic(rightEntries[key]), context)) {
      return false;
    }
  }
  return true;
}

int? _compare(_Value left, _Value right) {
  if (_isBlankString(left) || _isBlankString(right)) return null;
  if (left.kind == _ValueKind.string && right.kind == _ValueKind.string) {
    return (left.value as String).compareTo(right.value as String);
  }
  final leftNumber = _comparisonNumber(left);
  final rightNumber = _comparisonNumber(right);
  if (leftNumber == null || rightNumber == null) return null;
  return leftNumber.compareTo(rightNumber);
}

bool _isBlankString(_Value value) =>
    value.kind == _ValueKind.string &&
    _trimPortableWhitespace(value.value as String).isEmpty;

double? _comparisonNumber(_Value value) {
  if (value.kind == _ValueKind.number) {
    final number = value.value as double;
    return number.isFinite ? number : null;
  }
  if (value.kind == _ValueKind.string) {
    return _parseDecimalNumber(value.value as String);
  }
  return null;
}
