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

  test('preserves visited-pair handling for cyclic list equality', () {
    final left = <Object?>[1];
    final right = <Object?>[1];
    left.add(left);
    right.add(right);
    expect(
        executeExpression({'left': left, 'right': right}, 'eq(#left, #right)'),
        isTrue);

    final different = <Object?>[2];
    different.add(different);
    expect(
        executeExpression(
            {'left': left, 'right': different}, 'eq(#left, #right)'),
        isFalse);
  });

  test('equality uses explicit portable scalar and collection rules', () {
    for (final expression in [
      'eq(1, "1")',
      'eq(true, 1)',
      'eq(false, 0)',
      'eq(true, "1")',
      'eq(false, "0")',
      'eq(#missing, #value)',
      'eq([1, "2"], ["1", 2])',
    ]) {
      expect(executeExpression({'value': null}, expression), isTrue,
          reason: expression);
    }
    for (final expression in [
      'eq(true, "true")',
      'eq(false, "")',
      'eq(false, "   ")',
      'eq(0, "0x0")',
      'eq([], "")',
      'eq([1], 1)',
      'eq([1], #map)',
      'eq(#map, "[object Object]")',
    ]) {
      expect(
          executeExpression({'map': <String, Object?>{}}, expression), isFalse,
          reason: expression);
    }
  });

  test('comparisons are ordinal for strings and numeric for numeric pairs', () {
    for (final expression in [
      'lt("10", "2")',
      'gt("2", 1)',
      'lt(.5, "1e0")',
    ]) {
      expect(executeExpression({}, expression), isTrue, reason: expression);
    }
    for (final expression in [
      'lt("2", "10")',
      'gt(true, 0)',
      'lt(#missing, 1)',
      'lt(#value, 1)',
      'gt("", "a")',
      'lt("   ", "a")',
      'gt([], 0)',
      'lt(#map, "z")',
      'gt("invalid", 0)',
      'lt("0x10", 17)',
    ]) {
      expect(executeExpression({'value': null, 'map': {}}, expression), isFalse,
          reason: expression);
    }
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

  test('numeric strings use the finite decimal literal grammar', () {
    for (final entry in {
      '.5': 0.5,
      '5.': 5.0,
      '5.e3': 5000.0,
      '+2.5e-1': 0.25,
      '-.5E+1': -5.0,
    }.entries) {
      final model = {'value': entry.key};
      expect(parseExpression('num(#value)').evaluateValue(model), entry.value);
      expect(parseExpression('add(#value, 1)').evaluateValue(model),
          entry.value + 1);
      expect(executeExpression(model, 'eq(#value, ${entry.value})'), isTrue);
    }

    expect(parseExpression('num(.5)').evaluateValue({}), 0.5);
    expect(parseExpression('num(5.)').evaluateValue({}), 5.0);

    for (final value in [
      '0x10',
      '0Xff',
      '0b10',
      '0o10',
      '.',
      '+',
      '1_000',
      '1e',
    ]) {
      expect(
        () => parseExpression('num(#value)').evaluateValue({'value': value}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric value'))),
        reason: 'accepted $value',
      );
      expect(executeExpression({'value': value}, 'eq(#value, 16)'), isFalse);
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
    expect(() => parseExpression('1e999'),
        throwsA(isA<ExpressionParseException>()));
    expect(parseExpression('num(" 2.5 ")').evaluateValue({}), 2.5);
  });

  test('uses the explicit Unicode White_Space set', () {
    final whitespace = <int>[
      ...List.generate(5, (index) => 0x0009 + index),
      0x0020,
      0x0085,
      0x00a0,
      0x1680,
      ...List.generate(11, (index) => 0x2000 + index),
      0x2028,
      0x2029,
      0x202f,
      0x205f,
      0x3000,
    ];
    for (final code in whitespace) {
      final space = String.fromCharCode(code);
      expect(parseExpression('$space true$space').evaluateValue({}), isTrue,
          reason: 'expression U+${code.toRadixString(16)}');
      expect(parseExpression('add(1$space,${space}2)').evaluateValue({}), 3.0,
          reason: 'token U+${code.toRadixString(16)}');
      expect(
          parseExpression('trim(#value)')
              .evaluateValue({'value': '${space}x$space'}),
          'x',
          reason: 'trim U+${code.toRadixString(16)}');
      expect(
          parseExpression('num(#value)')
              .evaluateValue({'value': '${space}2$space'}),
          2.0,
          reason: 'numeric U+${code.toRadixString(16)}');
    }

    const bom = '\ufeff';
    expect(() => parseExpression('${bom}true$bom'), throwsFormatException);
    expect(
        parseExpression('trim(#value)').evaluateValue({'value': '${bom}x$bom'}),
        '${bom}x$bom');
    expect(
      () => parseExpression('num(#value)')
          .evaluateValue({'value': '${bom}2$bom'}),
      throwsA(predicate((error) => '$error'.contains('Invalid numeric value'))),
    );
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

  test('text conversion rejects active list cycles but permits reuse', () {
    final cyclic = <Object?>[];
    cyclic.add(cyclic);
    for (final expression in [
      'concat(#value, "")',
      'contains("x", #value)',
      'startswith("x", #value)',
      'endswith("x", #value)',
      'match(#value, "x")',
      'trim(#value)',
      'lower(#value)',
      'upper(#value)',
    ]) {
      expect(
        () => parseExpression(expression).evaluateValue({'value': cyclic}),
        throwsA(predicate((error) => '$error'.contains('Cyclic list value'))),
        reason: expression,
      );
    }

    final shared = <Object?>[1, 2];
    expect(
      parseExpression('concat(#value, "")').evaluateValue({
        'value': [shared, shared]
      }),
      '1,2,1,2',
    );
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
      final expression = parseExpression('$operator(1)');
      expect(
        () => expression.evaluateValue({}),
        throwsA(predicate((error) => '$error'
            .contains('operator $operator expects at least two arguments '
                'or one list argument'))),
      );
    }
  });

  test('evaluates and flattens all variadic arguments before conversion', () {
    expect(
      () => parseExpression('add("bad", sqrt(-1))').evaluateValue({}),
      throwsA(
          predicate((error) => '$error'.contains('Invalid numeric result'))),
    );
    expect(
      () => parseExpression('sub("bad", [])').evaluateValue({}),
      throwsA(predicate((error) => '$error'.contains('Invalid numeric value'))),
    );
  });

  test('supports round, power, and clamp', () {
    expect(parseExpression('round(12.345, 2)').evaluateValue({}), 12.35);
    expect(parseExpression('round(-12.345, 2)').evaluateValue({}), -12.35);
    expect(parseExpression('round(1.005, 2)').evaluateValue({}), 1.0);
    expect(parseExpression('round(-1.005, 2)').evaluateValue({}), -1.0);
    expect(
        parseExpression('round(1.0049999999999997, 2)').evaluateValue({}), 1.0);
    expect(parseExpression('round(1.0050000000000001, 2)').evaluateValue({}),
        1.01);
    expect(
        parseExpression('round(7.164692098702749e-215, 230)').evaluateValue({}),
        7.164692098702749e-215);
    expect(
        parseExpression('round(4.898568327955125e-190, 204)').evaluateValue({}),
        4.89856832795512e-190);
    expect(
        parseExpression('round(6.663776354903525e-38, 52)').evaluateValue({}),
        6.66377635490352e-38);
    expect(parseExpression('round(1e308, 308)').evaluateValue({}), 1e308);
    expect(parseExpression('round(5e-324, 308)').evaluateValue({}), 0.0);
    expect(parseExpression('round(1.25, "308")').evaluateValue({}), 1.25);
    expect(parseExpression('pow(2, 3)').evaluateValue({}), 8.0);
    expect(parseExpression('clamp(12, 0, 10)').evaluateValue({}), 10.0);
  });

  test('numeric results normalize negative zero', () {
    for (final expression in ['round(-0.4, 0)', 'mul(-1, 0)', 'ceil(-0.5)']) {
      final result = parseExpression(expression).evaluateValue({}) as double;
      expect(result, 0.0, reason: expression);
      expect(result.isNegative, isFalse, reason: expression);
    }

    final nested = <Object?>[-0.0];
    final returned =
        parseExpression('#value').evaluateValue({'value': nested}) as List;
    expect(identical(returned, nested), isTrue);
    expect((returned.single as double).isNegative, isTrue);

    final nestedMap = <String, Object?>{'number': -0.0};
    final returnedMap =
        parseExpression('#value').evaluateValue({'value': nestedMap}) as Map;
    expect(identical(returnedMap, nestedMap), isTrue);
    expect((returnedMap['number'] as double).isNegative, isTrue);
  });

  test('rounds decimal ties away from zero', () {
    expect(parseExpression('round(0.5, 0)').evaluateValue({}), 1.0);
    expect(parseExpression('round(-0.5, 0)').evaluateValue({}), -1.0);
    expect(parseExpression('round(2.5, 0)').evaluateValue({}), 3.0);
    expect(parseExpression('round(-2.5, 0)').evaluateValue({}), -3.0);
  });

  test('uses signed remainder and rejects invalid results', () {
    expect(parseExpression('mod(-7, 3)').evaluateValue({}), -1.0);
    expect(parseExpression('mod(7, -3)').evaluateValue({}), 1.0);
    expect(
        parseExpression('mod(#value, 3)').evaluateValue({'value': 1e308}), 2.0);
    expect(
      () => parseExpression('mod(7, pow(1e308, 2))').evaluateValue({}),
      throwsA(
          predicate((error) => '$error'.contains('Invalid numeric result'))),
    );
    expect(
      () => parseExpression('mod(pow(1e308, 2), 3)').evaluateValue({}),
      throwsA(
          predicate((error) => '$error'.contains('Invalid numeric result'))),
    );
  });

  test('every numeric operator rejects a nonfinite result', () {
    for (final expression in [
      'sqrt(-1)',
      'pow(1e308, 2)',
      'add(1e308, 1e308)',
      'sub(-1e308, 1e308)',
      'mul(1e308, 2)',
      'div(1e308, 1e-308)',
    ]) {
      expect(
        () => parseExpression(expression).evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric result'))),
        reason: expression,
      );
    }
  });

  test('literal regexes compile eagerly and runtime regexes compile on use',
      () {
    expect(() => parseExpression('match("x", "[")'),
        throwsA(isA<ExpressionParseException>()));
    final expression = parseExpression('match("x", #pattern)');
    expect(() => expression.evaluateValue({'pattern': '['}),
        throwsA(isA<ExpressionEvaluationException>()));

    expect(expression.evaluateValue({'pattern': 'x'}), isTrue);
    expect(expression.evaluateValue({'pattern': 'y'}), isFalse);
    expect(expression.evaluateValue({'pattern': 'x'}), isTrue);
  });

  test('min and max reject nonfinite inputs and normalize signed zero', () {
    expect(
        () => parseExpression('min(sqrt(-1), 1)').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric result'))));
    expect(
        () => parseExpression('max(1, sqrt(-1))').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('Invalid numeric result'))));

    final minimum = parseExpression('min(#positive, #negative)')
        .evaluateValue({'positive': 0.0, 'negative': -0.0}) as double;
    final maximum = parseExpression('max(#negative, #positive)')
        .evaluateValue({'positive': 0.0, 'negative': -0.0}) as double;
    expect(minimum.isNegative, isFalse);
    expect(maximum.isNegative, isFalse);
  });

  test('validates expression types before cache lookup', () {
    SimpleExpressions.enableCaches();
    SimpleExpressions.clear();
    SimpleExpressions.get('1');

    expect(() => SimpleExpressions.get(1), throwsArgumentError);
  });

  test('Boolean expressions share cache keys with lowercase strings', () {
    SimpleExpressions.enableCaches();
    SimpleExpressions.clear();

    final trueBoolean = SimpleExpressions.get(true);
    expect(trueBoolean, same(SimpleExpressions.get('true')));
    expect(trueBoolean.evaluateValue({}), isTrue);

    SimpleExpressions.clear(expression: true);
    final trueString = SimpleExpressions.get('true');
    expect(trueString, same(SimpleExpressions.get(true)));
    expect(trueString.evaluateValue({}), isTrue);

    expect(SimpleExpressions.get(false), same(SimpleExpressions.get('false')));
    expect(SimpleExpressions.get(true),
        isNot(same(SimpleExpressions.get('True'))));
  });

  test('rejects invalid mathematical operations', () {
    expect(() => parseExpression('div(1, 0)').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Division by zero'))));
    expect(() => parseExpression('round(1.2, -1)').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Round precision'))));
    expect(
        () => parseExpression('round(1.2, #places)')
            .evaluateValue({'places': 309}),
        throwsA(predicate((error) => '$error'.contains('too large'))));
    expect(() => parseExpression('min([])').evaluateValue({}),
        throwsA(predicate((error) => '$error'.contains('Min requires'))));
    expect(
        () => parseExpression('add(1)').evaluateValue({}),
        throwsA(
            predicate((error) => '$error'.contains('at least two arguments'))));
  });

  group('exception types', () {
    test('reports parse failures as ExpressionParseException', () {
      for (final expression in ['1e309', 'eq(1', 'match(#a, "(")']) {
        expect(() => parseExpression(expression),
            throwsA(isA<ExpressionParseException>()),
            reason: expression);
      }
    });

    test('reports runtime failures as ExpressionEvaluationException', () {
      expect(() => parseExpression('num("x")').evaluateValue({}),
          throwsA(isA<ExpressionEvaluationException>()));
      expect(() => parseExpression('div(1, 0)').evaluateValue({}),
          throwsA(isA<ExpressionEvaluationException>()));
      expect(() => parseExpression('match("a", #p)').evaluateValue({'p': '('}),
          throwsA(isA<ExpressionEvaluationException>()));
    });

    test('evaluates match input before the pattern', () {
      expect(
          () => parseExpression('match(num("x"), #p)').evaluateValue({'p': 1}),
          throwsA(isA<ExpressionEvaluationException>()));
    });

    test('keeps the numeric arity prefix and ternary wording', () {
      expect(
          () => parseExpression('add(#v)').evaluateValue({'v': 5}),
          throwsA(predicate((Object? e) => e.toString().contains(
              'Invalid Expression: operator add expects at least two'))));
      expect(
          () => parseExpression('if(1)'),
          throwsA(predicate(
              (Object? e) => e.toString().contains('three arguments'))));
    });

    test('keeps unsupported input as ArgumentError', () {
      expect(() => SimpleExpression(5), throwsArgumentError);
    });
  });
}
