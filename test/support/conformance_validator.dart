import 'package:simple_expressions/simple_expressions.dart';

/// Thrown when a conformance corpus document is malformed.
class ConformanceFormatError extends Error {
  ConformanceFormatError(this.message);

  final String message;

  @override
  String toString() => 'ConformanceFormatError: $message';
}

List<Map<String, dynamic>> validateCorpus(Object? decoded) {
  const topFields = {r'$comment', 'cases'};
  const expectationFields = {'value', 'truthy', 'error'};
  final nonWhitespace = RegExp(r'\S');
  const caseFields = {
    r'$comment',
    'id',
    'expression',
    'model',
    'value',
    'truthy',
    'error',
  };
  if (decoded is! Map<String, dynamic>) {
    throw ConformanceFormatError('Conformance document must be an object');
  }
  if (decoded.keys.any((field) => !topFields.contains(field))) {
    throw ConformanceFormatError(
        'Conformance document contains an unsupported field');
  }
  final comment = decoded[r'$comment'];
  if (decoded.containsKey(r'$comment') &&
      (comment is! List || comment.any((line) => line is! String))) {
    throw ConformanceFormatError(
        'Conformance document comment must be a string list');
  }
  final rawCases = decoded['cases'];
  if (rawCases is! List) {
    throw ConformanceFormatError(
        'Conformance document must contain a cases list');
  }

  final ids = <String>{};
  final cases = <Map<String, dynamic>>[];
  for (var index = 0; index < rawCases.length; index++) {
    final item = rawCases[index];
    if (item is! Map<String, dynamic>) {
      throw ConformanceFormatError('Conformance case $index must be an object');
    }
    if (item.keys.any((field) => !caseFields.contains(field))) {
      throw ConformanceFormatError(
          'Conformance case $index contains an unsupported field');
    }
    final id = item['id'];
    if (id is! String || !nonWhitespace.hasMatch(id) || !ids.add(id)) {
      throw ConformanceFormatError(
          'Conformance case $index has an invalid or duplicate id');
    }
    if (item['expression'] is! String) {
      throw ConformanceFormatError(
          'Conformance case $id must have a string expression');
    }
    if (item.containsKey(r'$comment') && item[r'$comment'] is! String) {
      throw ConformanceFormatError(
          'Conformance case $id comment must be a string');
    }
    if (item.containsKey('model')) _validateJsonValue(item['model'], id);
    if (item.containsKey('value')) _validateJsonValue(item['value'], id);
    if (item.containsKey('truthy') && item['truthy'] is! bool) {
      throw ConformanceFormatError(
          'Conformance case $id truthy value must be a boolean');
    }
    final error = item['error'];
    if (item.containsKey('error') &&
        (error is! String || !nonWhitespace.hasMatch(error))) {
      throw ConformanceFormatError(
          'Conformance case $id error must be a nonempty string');
    }
    final expectations = expectationFields.where(item.containsKey).length;
    if (expectations != 1) {
      throw ConformanceFormatError(
          'Conformance case $id must have one expectation');
    }
    cases.add(item);
  }
  return cases;
}

void _validateJsonValue(Object? value, String id) {
  if (value == null || value is bool || value is String) return;
  if (value is num) {
    if (!value.isFinite) {
      throw ConformanceFormatError(
          'Conformance case $id contains a nonfinite number');
    }
    return;
  }
  if (value is List) {
    for (final item in value) {
      _validateJsonValue(item, id);
    }
    return;
  }
  if (value is Map<String, dynamic>) {
    for (final item in value.values) {
      _validateJsonValue(item, id);
    }
    return;
  }
  throw ConformanceFormatError(
      'Conformance case $id contains a non-JSON value');
}

/// Compares a corpus value with an evaluated result. Numbers must be doubles
/// with matching sign, so `1` vs `1.0` and `-0.0` vs `0.0` are distinguished
/// from the JSON `0`/`-0` rules only where the evaluator can produce them.
bool matchesValue(Object? expected, Object? actual) {
  if (expected is num) {
    if (actual is! num) return false;
    final expectedDouble = expected.toDouble();
    return expectedDouble == actual.toDouble() &&
        expectedDouble.isNegative == actual.toDouble().isNegative;
  }
  if (expected is List) {
    if (actual is! List || expected.length != actual.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (!matchesValue(expected[index], actual[index])) return false;
    }
    return true;
  }
  if (expected is Map) {
    if (actual is! Map || expected.length != actual.length) return false;
    for (final entry in expected.entries) {
      if (!actual.containsKey(entry.key) ||
          !matchesValue(entry.value, actual[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return expected == actual;
}

/// Whether [error] is one of the library's exceptions with a message
/// containing [expected]. The exception type name never counts.
bool errorMatches(Object error, String expected) {
  if (error is ExpressionParseException) {
    return error.message.contains(expected);
  }
  if (error is ExpressionEvaluationException) {
    return error.message.contains(expected);
  }
  return false;
}
