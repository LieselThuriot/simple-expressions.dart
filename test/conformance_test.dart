import 'dart:convert';
import 'dart:io';

import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  final document = jsonDecode(
    File('test/fixtures/conformance/spec/v1/cases.json').readAsStringSync(),
  ) as Map<String, dynamic>;
  final cases = (document['cases'] as List).cast<Map<String, dynamic>>();

  for (final item in cases) {
    final expectations =
        ['value', 'truthy', 'error'].where(item.containsKey).length;
    if (expectations != 1) {
      throw StateError('Each case must have one expectation: ${item['id']}');
    }
  }

  for (final item in cases) {
    test('v1/${item['id']}', () {
      final expression = item['expression'] as String;
      final model = (item['model'] as Map?) ?? const <String, Object?>{};

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
          !_matches(entry.value, actual[entry.key])) return false;
    }
    return true;
  }
  return expected == actual;
}
