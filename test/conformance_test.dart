import 'dart:convert';
import 'dart:io';

import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  final decoded = jsonDecode(
    File('test/fixtures/conformance/spec/v1/cases.json').readAsStringSync(),
  );
  final cases = _validateCorpus(decoded);

  for (final item in cases) {
    test('v1/${item['id']}', () {
      final expression = item['expression'] as String;
      final model =
          item.containsKey('model') ? item['model'] : const <String, Object?>{};

      if (item.containsKey('error')) {
        final expected = item['error'] as String;
        expect(
          () => parseExpression(expression).evaluateValue(model),
          throwsA(predicate((Object error) => '$error'.contains(expected))),
        );
      } else if (item.containsKey('truthy')) {
        expect(executeExpression(model, expression), item['truthy']);
      } else {
        expect(
            _matches(item['value'],
                parseExpression(expression).evaluateValue(model)),
            isTrue);
      }
    });
  }
}

List<Map<String, dynamic>> _validateCorpus(Object? decoded) {
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
    throw StateError('Conformance document must be an object');
  }
  if (decoded.keys.any((field) => !topFields.contains(field))) {
    throw StateError('Conformance document contains an unsupported field');
  }
  final comment = decoded[r'$comment'];
  if (decoded.containsKey(r'$comment') &&
      (comment is! List || comment.any((line) => line is! String))) {
    throw StateError('Conformance document comment must be a string list');
  }
  final rawCases = decoded['cases'];
  if (rawCases is! List) {
    throw StateError('Conformance document must contain a cases list');
  }

  final ids = <String>{};
  final cases = <Map<String, dynamic>>[];
  for (var index = 0; index < rawCases.length; index++) {
    final item = rawCases[index];
    if (item is! Map<String, dynamic>) {
      throw StateError('Conformance case $index must be an object');
    }
    if (item.keys.any((field) => !caseFields.contains(field))) {
      throw StateError('Conformance case $index contains an unsupported field');
    }
    final id = item['id'];
    if (id is! String || !nonWhitespace.hasMatch(id) || !ids.add(id)) {
      throw StateError(
          'Conformance case $index has an invalid or duplicate id');
    }
    if (item['expression'] is! String) {
      throw StateError('Conformance case $id must have a string expression');
    }
    if (item.containsKey(r'$comment') && item[r'$comment'] is! String) {
      throw StateError('Conformance case $id comment must be a string');
    }
    if (item.containsKey('model')) _validateJsonValue(item['model'], id);
    if (item.containsKey('value')) _validateJsonValue(item['value'], id);
    if (item.containsKey('truthy') && item['truthy'] is! bool) {
      throw StateError('Conformance case $id truthy value must be a boolean');
    }
    final error = item['error'];
    if (item.containsKey('error') &&
        (error is! String || !nonWhitespace.hasMatch(error))) {
      throw StateError('Conformance case $id error must be a nonempty string');
    }
    final expectations = expectationFields.where(item.containsKey).length;
    if (expectations != 1) {
      throw StateError('Conformance case $id must have one expectation');
    }
    cases.add(item);
  }
  return cases;
}

void _validateJsonValue(Object? value, String id) {
  if (value == null || value is bool || value is String) return;
  if (value is num) {
    if (!value.isFinite) {
      throw StateError('Conformance case $id contains a nonfinite number');
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
  throw StateError('Conformance case $id contains a non-JSON value');
}

bool _matches(Object? expected, Object? actual) {
  if (expected is num && actual is num) {
    return expected.toDouble() == actual.toDouble();
  }
  if (expected is List) {
    if (actual is! List || expected.length != actual.length) return false;
    for (var index = 0; index < expected.length; index++) {
      if (!_matches(expected[index], actual[index])) return false;
    }
    return true;
  }
  if (expected is Map) {
    if (actual is! Map || expected.length != actual.length) return false;
    for (final entry in expected.entries) {
      if (!actual.containsKey(entry.key) ||
          !_matches(entry.value, actual[entry.key])) {
        return false;
      }
    }
    return true;
  }
  return expected == actual;
}
