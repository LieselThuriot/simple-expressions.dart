import 'dart:convert';
import 'dart:io';

import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

/// Runs the cross-implementation parity corpus shared with the TypeScript
/// reference and the C# port. The corpus is vendored at `test/parity/cases.json`;
/// the canonical copy lives in the TypeScript repository.
void main() {
  const implementation = 'dart';

  final document = jsonDecode(File('test/parity/cases.json').readAsStringSync())
      as Map<String, dynamic>;
  final allCases = (document['cases'] as List).cast<Map<String, dynamic>>();
  final cases = allCases
      .where((parityCase) =>
          !((parityCase['skip'] as List?)?.contains(implementation) ?? false))
      .toList();

  setUp(() {
    SimpleExpressions.enableCaches();
    SimpleExpressions.setCacheLimit(1000);
    SimpleExpressions.clear();
  });

  group('shared parity corpus', () {
    test('every case id is unique', () {
      final ids = allCases.map((parityCase) => parityCase['id']).toSet();
      expect(ids, hasLength(allCases.length));
    });

    test('every case declares exactly one expectation', () {
      for (final parityCase in allCases) {
        final declared = ['value', 'truthy', 'error']
            .where(parityCase.containsKey)
            .toList();
        expect(declared, hasLength(1), reason: '${parityCase['id']}');
      }
    });

    for (final parityCase in cases) {
      test(parityCase['id'] as String, () {
        final expression = parityCase['expression'] as String;
        final model = (parityCase['model'] as Map?) ?? const <String, Object?>{};

        if (parityCase.containsKey('error')) {
          final expected = parityCase['error'] as String;
          expect(
            () => parseExpression(expression).evaluateValue(model),
            throwsA(predicate((Object error) => '$error'.contains(expected))),
          );
          return;
        }

        if (parityCase.containsKey('truthy')) {
          expect(executeExpression(model, expression), parityCase['truthy']);
          return;
        }

        final actual = parseExpression(expression).evaluateValue(model);
        expect(_matches(parityCase['value'], actual), isTrue,
            reason: 'expected ${parityCase['value']} but got $actual');
      });
    }
  });
}

/// Compares a decoded JSON expectation against an evaluated value, treating all
/// numbers as doubles so that a JSON `12` matches the evaluator's `12.0`.
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
  return expected == actual;
}
