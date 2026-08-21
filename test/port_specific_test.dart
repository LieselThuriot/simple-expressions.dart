import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  test('supports structural equality for port models', () {
    expect(
      executeExpression({
        'a': [1, 2],
        'b': [1, 2],
      }, 'eq(#a, #b)'),
      isTrue,
    );
    expect(
      executeExpression({
        'a': [
          1,
          [2, 3]
        ],
        'b': [
          1,
          [2, 3]
        ],
      }, 'eq(#a, #b)'),
      isTrue,
    );
    expect(
      executeExpression({
        'a': {'x': 1},
        'b': {'x': 1},
      }, 'eq(#a, #b)'),
      isTrue,
    );
  });

  test('handles cyclic objects without a depth limit', () {
    final left = <String, Object?>{'value': 1};
    final right = <String, Object?>{'value': 1};
    left['self'] = left;
    right['self'] = right;

    expect(
        executeExpression({'left': left, 'right': right}, 'eq(#left, #right)'),
        isTrue);
  });

  test('does not convert empty or blank strings to zero', () {
    expect(executeExpression({'value': ''}, 'eq(#value, 0)'), isFalse);
    expect(executeExpression({'value': '   '}, 'eq(#value, 0)'), isFalse);
  });

  test('positive cache limits do not re-enable caching', () {
    SimpleExpressions.disableCaches();
    SimpleExpressions.setCacheLimit(10);

    expect(SimpleExpressions.get('true'),
        isNot(same(SimpleExpressions.get('true'))));
  });

  test('invalid cache limits throw without changing cache state', () {
    expect(() => SimpleExpressions.setCacheLimit(0), throwsArgumentError);

    SimpleExpressions.enableCaches();
    expect(() => SimpleExpressions.setCacheLimit(-1), throwsArgumentError);
    expect(SimpleExpressions.get('true'), same(SimpleExpressions.get('true')));
  });

  test('supports unary mathematical operators', () {
    expect(parseExpression('int(-2.9)').evaluateValue({}), -2.0);
    expect(parseExpression('num("2.5")').evaluateValue({}), 2.5);
    expect(parseExpression('abs(-4)').evaluateValue({}), 4.0);
    expect(parseExpression('floor(2.9)').evaluateValue({}), 2.0);
    expect(parseExpression('ceil(2.1)').evaluateValue({}), 3.0);
    expect(parseExpression('sqrt(9)').evaluateValue({}), 3.0);
  });

  test('num rejects lists and NaN strings', () {
    expect(
        () => parseExpression('num([1])').evaluateValue({}), throwsStateError);
    expect(() => parseExpression('num(#value)').evaluateValue({'value': []}),
        throwsStateError);
    expect(() => parseExpression('num("NaN")').evaluateValue({}),
        throwsStateError);
  });

  test('supports arithmetic operators and numeric list expansion', () {
    expect(parseExpression('add([1, 2, 3], 4)').evaluateValue({}), 10.0);
    expect(parseExpression('add([1, 2, 3])').evaluateValue({}), 6.0);
    expect(parseExpression('sub(20, 5, 2)').evaluateValue({}), 13.0);
    expect(parseExpression('mul([2, 3])').evaluateValue({}), 6.0);
    expect(parseExpression('div(20, 5, 2)').evaluateValue({}), 2.0);
    expect(parseExpression('mod(17, 5)').evaluateValue({}), 2.0);
    expect(parseExpression('min([4, 2, 8])').evaluateValue({}), 2.0);
    expect(parseExpression('max(1, [4, 2], 3)').evaluateValue({}), 4.0);
  });

  test('supports round, power, and clamp', () {
    expect(parseExpression('round(12.345, 2)').evaluateValue({}), 12.35);
    expect(parseExpression('pow(2, 3)').evaluateValue({}), 8.0);
    expect(parseExpression('clamp(12, 0, 10)').evaluateValue({}), 10.0);
  });

  test('matches JavaScript remainder edge cases', () {
    expect(parseExpression('mod(-7, 3)').evaluateValue({}), -1.0);
    expect(parseExpression('mod(7, -3)').evaluateValue({}), 1.0);
    expect(
        parseExpression('mod(#value, 3)').evaluateValue({'value': 1e308}), 2.0);
    expect(
        parseExpression('mod(7, #value)')
            .evaluateValue({'value': double.infinity}),
        7.0);
    expect(
        (parseExpression('mod(#value, 3)')
                .evaluateValue({'value': double.infinity}) as double)
            .isNaN,
        isTrue);
  });

  test('min and max propagate NaN and preserve signed zero', () {
    expect(
        (parseExpression('min(sqrt(-1), 1)').evaluateValue({}) as double).isNaN,
        isTrue);
    expect(
        (parseExpression('max(1, sqrt(-1))').evaluateValue({}) as double).isNaN,
        isTrue);

    final minimum = parseExpression('min(#positive, #negative)')
        .evaluateValue({'positive': 0.0, 'negative': -0.0}) as double;
    final maximum = parseExpression('max(#negative, #positive)')
        .evaluateValue({'positive': 0.0, 'negative': -0.0}) as double;
    expect(minimum.isNegative, isTrue);
    expect(maximum.isNegative, isFalse);
  });

  test('validates expression types before cache lookup', () {
    SimpleExpressions.enableCaches();
    SimpleExpressions.clear();
    SimpleExpressions.get('1');

    expect(() => SimpleExpressions.get(1), throwsArgumentError);
  });

  test('rejects invalid mathematical operations', () {
    expect(() => parseExpression('div(1, 0)').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Division by zero'))));
    expect(() => parseExpression('round(1.2, -1)').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Round precision'))));
    expect(
        () => parseExpression('round(1.2, #places)')
            .evaluateValue({'places': 9007199254740992}),
        throwsA(predicate(
            (error) => '$error'.contains('non-negative safe integer'))));
    expect(() => parseExpression('min([])').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Min requires'))));
    expect(
        () => parseExpression('add(1)').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('at least two arguments'))));
  });
}
