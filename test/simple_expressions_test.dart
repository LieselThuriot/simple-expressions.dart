import 'package:simple_expressions/simple_expressions.dart';
import 'package:test/test.dart';

void main() {
  setUp(() {
    SimpleExpressions.enableCaches();
    SimpleExpressions.setCacheLimit(1000);
    SimpleExpressions.clear();
  });

  tearDown(() {
    SimpleExpressions.enableCaches();
    SimpleExpressions.setCacheLimit(1000);
    SimpleExpressions.clear();
  });

  group('basic expressions', () {
    test('evaluates boolean and string constants', () {
      expect(executeExpression({}, true), isTrue);
      expect(executeExpression({}, false), isFalse);
      expect(executeExpression({}, 'true'), isTrue);
      expect(executeExpression({}, 'FALSE'), isFalse);
    });

    test('supports variadic logical operators and nested references', () {
      expect(
        executeExpression(
          {'text': 'test'},
          'and(true, not(empty(#text)), lt(2, 10), true)',
        ),
        isTrue,
      );
      expect(executeExpression({}, 'or(false, false, true, false)'), isTrue);
      expect(executeExpression({}, 'and(true, true, false, true)'), isFalse);
    });
  });

  group('values and operators', () {
    test('parses numbers, strings, lists, and preserves value results', () {
      expect(parseExpression('+12').evaluateValue({}), 12.0);
      expect(parseExpression('-.5').evaluateValue({}), -0.5);
      expect(parseExpression('1e3').evaluateValue({}), 1000.0);
      expect(parseExpression('`backtick`').evaluateValue({}), 'backtick');
      expect(
        parseExpression('[1, lower("YES"), [true, 2]]').evaluateValue({}),
        [
          1.0,
          'yes',
          [true, 2.0]
        ],
      );
    });

    test('supports string operators and coercing operators', () {
      final model = {'value': 'Hello world'};
      expect(executeExpression(model, 'contains(#value, "world")'), isTrue);
      expect(executeExpression(model, 'startswith(#value, "Hello")'), isTrue);
      expect(executeExpression(model, 'endswith(#value, "World")'), isFalse);
      expect(parseExpression('lower(123)').evaluateValue({}), '123');
      expect(parseExpression('upper(false)').evaluateValue({}), '');
      expect(parseExpression('trim("  hello  ")').evaluateValue({}), 'hello');
    });

    test('supports length, membership, concatenation, and if', () {
      expect(
          executeExpression({
            'items': [1, 2, 3]
          }, 'eq(len(#items), 3)'),
          isTrue);
      expect(executeExpression({}, 'in(1, ["1", 2])'), isTrue);
      expect(
          parseExpression('concat("a", 0, false, #missing, "b")')
              .evaluateValue({}),
          'ab');
      expect(
          parseExpression('if(true, "yes", len(#value))')
              .evaluateValue({'value': {}}),
          'yes');
      expect(
          parseExpression('if(false, len(#value), "no")')
              .evaluateValue({'value': {}}),
          'no');
    });

    test('preserves TypeScript-style loose comparisons and truthiness', () {
      expect(executeExpression({}, 'eq(1, "1")'), isTrue);
      expect(executeExpression({}, 'eq(false, 0)'), isTrue);
      expect(executeExpression({'value': null}, 'eq(#value, 0)'), isFalse);
      expect(executeExpression({}, 'gt(10, 2)'), isTrue);
      expect(executeExpression({'value': 0}, 'empty(#value)'), isFalse);
      expect(executeExpression({'value': []}, 'empty(#value)'), isFalse);
      expect(executeExpression({}, 'defined("")'), isTrue);
      expect(executeExpression({}, 'defined(#missing)'), isFalse);
    });
  });

  group('references and missing values', () {
    test('prefers exact dotted keys over nested maps', () {
      final expression = parseExpression('#user.name');
      expect(
        expression.evaluateValue({
          'user': {'name': 'nested'},
          'user.name': 'direct',
        }),
        'direct',
      );
      expect(
          expression.evaluateValue({
            'user': {'name': 'nested'}
          }),
          'nested');
    });

    test('returns null publicly for missing values while preserving semantics',
        () {
      expect(parseExpression('#missing').evaluateValue({}), isNull);
      expect(parseExpression('trim(#missing)').evaluateValue({}), isNull);
      expect(executeExpression({}, 'defined(#missing)'), isFalse);
      expect(executeExpression({}, 'empty(#missing)'), isTrue);
      expect(executeExpression({}, 'eq(#missing, false)'), isFalse);
    });

    test('rejects unsafe and malformed references', () {
      for (final expression in [
        '#',
        '#.value',
        '#value.',
        '#value..child',
        '#__proto__',
        '#value.constructor',
        '#value.prototype.name',
      ]) {
        expect(() => parseExpression(expression),
            throwsA(isA<ExpressionParseException>()));
      }
    });
  });

  group('lazy evaluation and regular expressions', () {
    test('short-circuits logical and conditional branches', () {
      final model = {'value': <String, Object?>{}};
      expect(executeExpression(model, 'and(false, len(#value))'), isFalse);
      expect(executeExpression(model, 'or(true, len(#value))'), isTrue);
      expect(
          parseExpression('if(true, "yes", len(#value))').evaluateValue(model),
          'yes');
    });

    test('matches constant and model-provided Dart regular expressions', () {
      expect(executeExpression({'value': 'hello'}, r'match(#value, "^hello$")'),
          isTrue);
      expect(
          executeExpression({'value': 'goodbye'}, r'match(#value, "^hello$")'),
          isFalse);
      final expression = parseExpression('match(#value, #pattern)');
      expect(
          expression.evaluateValue({'value': 'hello', 'pattern': r'^hello$'}),
          isTrue);
      expect(
          expression.evaluateValue({'value': 'goodbye', 'pattern': r'^hello$'}),
          isFalse);
      expect(
          executeExpression(
              {'value': 'hello', 'pattern': 123}, 'match(#value, #pattern)'),
          isFalse);
    });
  });

  group('validation and caching', () {
    test('rejects malformed expressions', () {
      for (final expression in [
        '',
        '   ',
        'not()',
        'eq(1)',
        'eq(1,)',
        'eq(,1)',
        'and(true)',
        'concat("value")',
        'eq(1, 2) trailing',
        '[1,]',
        'xor(true, false)',
        'null',
      ]) {
        expect(() => parseExpression(expression),
            throwsA(isA<ExpressionParseException>()));
      }
    });

    test('supports FIFO cache limits and disabling caches', () {
      SimpleExpressions.setCacheLimit(1);
      final first = SimpleExpressions.get('true');
      SimpleExpressions.get('false');
      expect(identical(first, SimpleExpressions.get('true')), isFalse);

      SimpleExpressions.disableCaches();
      expect(
        identical(SimpleExpressions.get('true'), SimpleExpressions.get('true')),
        isFalse,
      );
    });

    test('supports the bool-capable Expression constructor', () {
      expect(Expression(true).evaluate({}), isTrue);
      expect(Expression(false).evaluate({}), isFalse);
      expect(() => Expression(123), throwsArgumentError);
    });
  });
}
