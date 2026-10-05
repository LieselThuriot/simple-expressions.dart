import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

import 'support/conformance_validator.dart';

Map<String, Object?> ok() => {'id': 'a', 'expression': 'true', 'truthy': true};
Map<String, Object?> corpus(List<Object?> cases) => {'cases': cases};

void main() {
  test('accepts a valid corpus', () {
    expect(
        validateCorpus(corpus([
          ok(),
          {'id': 'b', 'expression': '1', 'value': 1},
          {'id': 'c', 'expression': 'x', 'error': 'e'},
        ])),
        hasLength(3));
  });

  final invalid = <String, Object?>{
    'non-object document': <Object?>[],
    'unknown top-level field': {'cases': <Object?>[], 'extra': 1},
    'cases not a list': {'cases': <String, Object?>{}},
    'non-list document comment': {r'$comment': 'x', 'cases': <Object?>[]},
    'non-object case': corpus([1]),
    'unknown case field': corpus([ok()..['extra'] = 1]),
    'blank id': corpus([ok()..['id'] = ' ']),
    'non-string expression': corpus([ok()..['expression'] = 1]),
    'duplicate id': corpus([ok(), ok()]),
    'zero expectations': corpus([
      {'id': 'a', 'expression': 'true'}
    ]),
    'value and truthy': corpus([ok()..['value'] = 1]),
    'value and error': corpus([
      {'id': 'a', 'expression': 'x', 'value': 1, 'error': 'e'}
    ]),
    'truthy and error': corpus([ok()..['error'] = 'e']),
    'non-boolean truthy': corpus([
      {'id': 'a', 'expression': 'x', 'truthy': 1}
    ]),
    'non-string error': corpus([
      {'id': 'a', 'expression': 'x', 'error': 1}
    ]),
    'blank error': corpus([
      {'id': 'a', 'expression': 'x', 'error': ' '}
    ]),
    'non-finite value': corpus([
      {'id': 'a', 'expression': 'x', 'value': double.infinity}
    ]),
    'NaN model': corpus([
      ok()..['model'] = {'a': double.nan}
    ]),
    'non-JSON value': corpus([
      {'id': 'a', 'expression': 'x', 'value': DateTime(2000)}
    ]),
  };
  invalid.forEach((name, input) {
    test('rejects $name', () {
      expect(
          () => validateCorpus(input), throwsA(isA<ConformanceFormatError>()));
    });
  });

  group('matchesValue', () {
    test('requires equal numbers and matching zero sign', () {
      expect(matchesValue(1, 1.0), isTrue);
      expect(matchesValue(1, 1), isTrue);
      expect(matchesValue(1, 2.0), isFalse);
      expect(matchesValue('1', 1), isFalse);
      expect(matchesValue(0, -0.0), isFalse);
      expect(matchesValue(0, 0.0), isTrue);
      expect(matchesValue([1, 'a'], [1.0, 'a']), isTrue);
      expect(matchesValue([1], <Object?>[]), isFalse);
      expect(matchesValue({'a': 1}, {'a': 1.0}), isTrue);
      expect(matchesValue({'a': 1}, {'b': 1.0}), isFalse);
    });
  });

  group('errorMatches', () {
    test('matches messages of library exceptions only', () {
      expect(
          errorMatches(
              ExpressionEvaluationException('Division by zero'), 'zero'),
          isTrue);
      expect(errorMatches(ExpressionParseException('bad', 3), 'bad'), isTrue);
      expect(errorMatches(ExpressionEvaluationException('x'), 'Evaluation'),
          isFalse);
      expect(errorMatches(StateError('zero'), 'zero'), isFalse);
    });
  });
}
