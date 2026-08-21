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
