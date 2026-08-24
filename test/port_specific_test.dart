import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  tearDown(() {
    SimpleExpressions.disableCaches();
    SimpleExpressions.setCacheLimit(1000);
    SimpleExpressions.enableCaches();
  });

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

  test('accepts a null model root without replacing it', () {
    expect(parseExpression('defined(#value)').evaluateValue(null), isFalse);
    expect(executeExpression(null, 'empty(#value)'), isTrue);
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

  test('cache clear, disable, and FIFO limit lifecycle is consistent', () {
    SimpleExpressions.enableCaches();
    SimpleExpressions.clear();
    SimpleExpressions.setCacheLimit(2);

    final first = SimpleExpressions.get('true');
    final second = SimpleExpressions.get('false');
    expect(SimpleExpressions.get('true'), same(first));

    SimpleExpressions.get('eq(1, 1)');
    expect(SimpleExpressions.get('false'), same(second));
    expect(SimpleExpressions.get('true'), isNot(same(first)));

    SimpleExpressions.clear(parsed: true);
    final cached = SimpleExpressions.get('true');
    SimpleExpressions.clear(expression: true);
    expect(SimpleExpressions.get('true'), isNot(same(cached)));

    final beforeDisable = SimpleExpressions.get('false');
    SimpleExpressions.disableCaches();
    SimpleExpressions.enableCaches();
    expect(SimpleExpressions.get('false'), isNot(same(beforeDisable)));
  });

  test('supports unary mathematical operators', () {
    expect(parseExpression('int(-2.9)').evaluateValue({}), -2.0);
    expect(parseExpression('num("2.5")').evaluateValue({}), 2.5);
    expect(parseExpression('abs(-4)').evaluateValue({}), 4.0);
    expect(parseExpression('floor(2.9)').evaluateValue({}), 2.0);
    expect(parseExpression('ceil(2.1)').evaluateValue({}), 3.0);
    expect(parseExpression('sqrt(9)').evaluateValue({}), 3.0);
  });

  test('numeric strings use JavaScript radix grammar', () {
    for (final entry in {
      '0x10': 16.0,
      '0X10000000000000000': 18446744073709551616.0,
      '0b10': 2.0,
      '0o10': 8.0,
    }.entries) {
      final model = {'value': entry.key};
      expect(parseExpression('num(#value)').evaluateValue(model), entry.value);
      expect(parseExpression('add(#value, 1)').evaluateValue(model),
          entry.value + 1);
      expect(executeExpression(model, 'eq(#value, ${entry.value})'), isTrue);
    }
  });

  test('numeric scalars must be finite numbers or finite numeric strings', () {
    expect(
        () => parseExpression('num([1])').evaluateValue({}), throwsStateError);
    for (final value in <Object?>[
      true,
      null,
      const <String, Object?>{},
      const <Object?>[],
      '',
      '   ',
      'invalid',
      'NaN',
      'Infinity',
      double.nan,
      double.infinity,
      double.negativeInfinity,
    ]) {
      expect(
        () => parseExpression('num(#value)').evaluateValue({'value': value}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))),
        reason: 'accepted $value',
      );
    }
    expect(() => parseExpression('num(#missing)').evaluateValue({}),
        throwsStateError);
    expect(() => parseExpression('num(1e999)').evaluateValue({}),
        throwsStateError);
    expect(parseExpression('num(" 2.5 ")').evaluateValue({}), 2.5);
  });

  test('recursively flattens numeric lists depth first', () {
    final model = {
      'values': [
        20,
        [
          5,
          [2]
        ]
      ],
    };

    expect(parseExpression('add([1, [2, [3]]], 4)').evaluateValue({}), 10.0);
    expect(parseExpression('add(#values)').evaluateValue(model), 27.0);
    expect(parseExpression('sub(20, 5, 2)').evaluateValue({}), 13.0);
    expect(parseExpression('sub(#values)').evaluateValue(model), 13.0);
    expect(parseExpression('mul([[2], [3]])').evaluateValue({}), 6.0);
    expect(parseExpression('div(20, 5, 2)').evaluateValue({}), 2.0);
    expect(parseExpression('div(#values)').evaluateValue(model), 2.0);
    expect(parseExpression('mod(17, 5)').evaluateValue({}), 2.0);
    expect(parseExpression('mod([[17], [5]])').evaluateValue({}), 2.0);
    expect(parseExpression('min([4, 2, 8])').evaluateValue({}), 2.0);
    expect(parseExpression('max(1, [4, 2], 3)').evaluateValue({}), 4.0);
    expect(parseExpression('add([])').evaluateValue({}), 0.0);
    expect(parseExpression('mul([])').evaluateValue({}), 1.0);
  });

  test('rejects invalid numeric leaves and active list cycles', () {
    for (final expression in [
      'add(#values)',
      'sub(#values)',
      'mul(#values)',
      'div(#values)',
      'mod(#values)',
      'min(#values)',
      'max(#values)',
    ]) {
      expect(
        () => parseExpression(expression).evaluateValue({
          'values': [1, true]
        }),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))),
      );
    }

    final cyclic = <Object?>[1];
    cyclic.add(cyclic);
    expect(
      () => parseExpression('add(#values)').evaluateValue({'values': cyclic}),
      throwsA(predicate((error) => '$error'.contains('Invalid numeric value'))),
    );

    final shared = <Object?>[1, 2];
    expect(
        parseExpression('add(#values)').evaluateValue({
          'values': [shared, shared]
        }),
        6.0);
  });

  test('enforces numeric leaf counts after flattening', () {
    expect(parseExpression('min([[1]])').evaluateValue({}), 1.0);
    expect(parseExpression('max([[1]])').evaluateValue({}), 1.0);
    for (final expression in ['sub([1])', 'div([1])', 'mod([1])']) {
      expect(
        () => parseExpression(expression).evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('at least two values'))),
      );
    }
    for (final expression in ['min([])', 'max([])']) {
      expect(() => parseExpression(expression).evaluateValue({}),
          throwsStateError);
    }
  });

  test('one scalar argument reports the portable list alternative', () {
    for (final operator in ['add', 'sub', 'mul', 'div', 'mod', 'min', 'max']) {
      expect(
        () => parseExpression('$operator(1)').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains(
            'operator $operator expects at least two arguments or one list argument'))),
      );
    }
  });

  test('supports round, power, and clamp', () {
    expect(parseExpression('round(12.345, 2)').evaluateValue({}), 12.35);
    expect(parseExpression('pow(2, 3)').evaluateValue({}), 8.0);
    expect(parseExpression('clamp(12, 0, 10)').evaluateValue({}), 10.0);
  });

  test('round preserves JavaScript negative zero', () {
    final result =
        parseExpression('round(-0.5, 0)').evaluateValue({}) as double;
    expect(result, 0.0);
    expect(result.isNegative, isTrue);
  });

  test('matches JavaScript remainder edge cases', () {
    expect(parseExpression('mod(-7, 3)').evaluateValue({}), -1.0);
    expect(parseExpression('mod(7, -3)').evaluateValue({}), 1.0);
    expect(
        parseExpression('mod(#value, 3)').evaluateValue({'value': 1e308}), 2.0);
    expect(
      () => parseExpression('mod(7, pow(1e308, 2))').evaluateValue({}),
      throwsA(predicate((error) => '$error'.contains('Invalid numeric value'))),
    );
    expect(
      () => parseExpression('mod(pow(1e308, 2), 3)').evaluateValue({}),
      throwsA(predicate((error) => '$error'.contains('Invalid numeric value'))),
    );
  });

  test('allows nonfinite results only at the top numeric level', () {
    expect((parseExpression('sqrt(-1)').evaluateValue({}) as double).isNaN,
        isTrue);
    expect(
        (parseExpression('pow(1e308, 2)').evaluateValue({}) as double)
            .isInfinite,
        isTrue);
    for (final expression in [
      'abs(sqrt(-1))',
      'add(pow(1e308, 2), 1)',
      'pow(2, sqrt(-1))',
      'clamp(pow(1e308, 2), 0, 1)',
    ]) {
      expect(
        () => parseExpression(expression).evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))),
        reason: expression,
      );
    }
  });

  test('literal regexes compile eagerly and runtime regexes compile on use',
      () {
    expect(() => parseExpression('match("x", "[")'), throwsFormatException);
    final expression = parseExpression('match("x", #pattern)');
    expect(() => expression.evaluateValue({'pattern': '['}),
        throwsFormatException);

    expect(expression.evaluateValue({'pattern': 'x'}), isTrue);
    expect(expression.evaluateValue({'pattern': 'y'}), isFalse);
    expect(expression.evaluateValue({'pattern': 'x'}), isTrue);
  });

  test('min and max reject nonfinite inputs and preserve signed zero', () {
    expect(
        () => parseExpression('min(sqrt(-1), 1)').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))));
    expect(
        () => parseExpression('max(1, sqrt(-1))').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))));

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
