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
    test('simple true results in true', () {
      expect(executeExpression({}, true), isTrue);
    });

    test('simple false results in false', () {
      expect(executeExpression({}, false), isFalse);
    });

    test('true results in true', () {
      expect(executeExpression({}, 'true'), isTrue);
    });

    test('false results in false', () {
      expect(executeExpression({}, 'false'), isFalse);
    });

    test('and not eq lt for 2 results in true', () {
      expect(
        executeExpression({'2': 2}, 'and( not(eq(#2, 5)), lt(#2, 10) )'),
        isTrue,
      );
    });

    test('and not eq lt for 12 results in false', () {
      expect(
        executeExpression({'2': 12}, 'and( not(eq(#2, 5)), lt(#2, 10) )'),
        isFalse,
      );
    });

    test('true and false work for empty models', () {
      expect(executeExpression({}, true), isTrue);
      expect(executeExpression({}, false), isFalse);
    });

    test('or and AND are case-insensitive', () {
      expect(executeExpression({}, 'or (true, false )'), isTrue);
      expect(executeExpression({}, 'AND (true, false )'), isFalse);
    });

    test('AND and OR accept more than two arguments', () {
      expect(executeExpression({}, 'AND(true, false, true, true, false)'),
          isFalse);
      expect(
          executeExpression({}, 'AND(true, true, true, true, true)'), isTrue);
      expect(executeExpression({}, 'OR(false, false, true, false, false)'),
          isTrue);
      expect(executeExpression({}, 'OR(false, false, false, false, false)'),
          isFalse);
    });

    test('AND handles falsey and truthy values', () {
      expect(executeExpression({}, 'AND (true, 0 )'), isFalse);
      expect(executeExpression({}, 'AND (true, "blub" )'), isTrue);
    });

    test('AND handles simple and nested model references', () {
      expect(
        executeExpression(
            {'text': 'test'}, 'AND (true, not( empty( #text )) )'),
        isTrue,
      );
      expect(
        executeExpression({'text': ''}, 'AND (true, not( empty( #text )) )'),
        isFalse,
      );
      expect(
        executeExpression({}, 'AND (true, not( empty( #text )) )'),
        isFalse,
      );
      expect(
        executeExpression(
          {
            'text': {'innerText': 'test'}
          },
          'AND (true, not( empty( #text.innerText )) )',
        ),
        isTrue,
      );
      expect(
        executeExpression(
          {
            'text': {'innerText': 'test'}
          },
          'AND (true, empty( #text.innerText ) )',
        ),
        isFalse,
      );
    });
  });

  group('string parsing and boundaries', () {
    test('too many quotes throw', () {
      expect(
        () => executeExpression({}, r'eq("te\""st", "te\""st")'),
        throwsException,
      );
    });

    test('invalid constant locations throw', () {
      for (final expression in [
        r'eq("test", "test"")',
        r'eq("test", "tes"t")',
        r'eq("te"st", "test")',
        r'eq("test"", "test")',
        r'eq("te""st", "test")',
        r'eq("te""st", "test"""""d")',
        r'eq(",""," ",")',
        r'eq("test", "test\")',
        r'eq("test\", "test")',
        r'eq(123, "test\" " " )',
        r'eq("test\" " ", 123 )',
      ]) {
        expect(() => executeExpression({}, expression), throwsException);
      }
    });

    test('invalid parameters throw', () {
      expect(
        () => executeExpression({}, r'eq("test", "test", "test")'),
        throwsException,
      );
      expect(
        () => executeExpression({}, r'not("test", "test")'),
        throwsException,
      );
    });

    test('constant boundaries are respected', () {
      expect(
        executeExpression(
          {},
          r'AND(eq("te\"st", "te\"st"), not(eq("te,st", "tes,t")))',
        ),
        isTrue,
      );
      expect(executeExpression({}, r'eq("test", "test\", \"test")'), isFalse);
      expect(
        executeExpression({}, r'eq("test\", \"test", "test\", \"test")'),
        isTrue,
      );
      expect(
        executeExpression({}, '''eq("test", "test', 'test")'''),
        isFalse,
      );
      expect(
        executeExpression({}, '''eq("test', 'test", "test', 'test")'''),
        isTrue,
      );
      expect(executeExpression({}, r'not(eq("tru\"e", "tru\"e"))'), isFalse);
      expect(executeExpression({}, r'eq(",", ",")'), isTrue);
      expect(executeExpression({}, r'eq("\",\"", "\",\"")'), isTrue);
      expect(executeExpression({}, r'''eq("','", "','")'''), isTrue);
      expect(executeExpression({}, r'eq(123, "test\"" )'), isFalse);
    });
  });

  group('regular expressions', () {
    test('can match a regex', () {
      expect(
          executeExpression(
              {'test': 'why hello there'}, r'match(#test, "hello")'),
          isTrue);
      expect(
          executeExpression(
              {'test': 'why hello there'}, r'match(#test, "^hello")'),
          isFalse);
      expect(
          executeExpression(
              {'test': 'why hello there'}, r'match(#test, "hello$")'),
          isFalse);
      expect(executeExpression({'test': 'hello'}, r'match(#test, "^hello$")'),
          isTrue);
      expect(executeExpression({'test': 'hello'}, r'match(#test, "[a-z]+")'),
          isTrue);
      expect(executeExpression({'test': '12345'}, r'match(#test, "[a-z]+")'),
          isFalse);
      expect(
          executeExpression({'test': ''}, r'match(#test, "[a-z]+")'), isFalse);
      expect(executeExpression({'test': ''}, r'match(#test, ".{0}")'), isTrue);
      expect(executeExpression({}, r'match(#test, ".+")'), isFalse);
      expect(executeExpression({'test': '123'}, r'match(#test, "")'), isFalse);
      expect(
        executeExpression(
            {'mail': 'test@test.com'}, r'match(#mail, "^[^@]+@[^@]+\.[^@]+$")'),
        isTrue,
      );
      expect(
        executeExpression({'mail': 'test@test.com'},
            r'''match(#mail, "^[^@]+@[^@]+\.[^@]+$")'''),
        isTrue,
      );
      expect(
        executeExpression(
            {'mail': 'test@test'}, r'''match(#mail, '^[^@]+@[^@]+\.[^@]+$')'''),
        isFalse,
      );
      expect(
        executeExpression({'mail': 'test@test.com'},
            r'''match(#mail, '^[^@]+@[^@]+\.[^@]+$')'''),
        isTrue,
      );
      expect(
        executeExpression({'mail': 'test@test.com'},
            r'AND(NOT(EMPTY(#mail)), MATCH(#mail, "^test@test.com$"))'),
        isTrue,
      );
      expect(
        executeExpression(
          {
            'form': {'mail': 'test@test.com'}
          },
          r'AND(NOT(EMPTY(#form.mail)), MATCH(#form.mail, "^test@test.com$"))',
        ),
        isTrue,
      );
    });

    test('can match two regexes and compose complex expressions', () {
      expect(
        executeExpression(
          {'test': 'why hello there'},
          r'and(match(#test, "hello"), match(#test, "there"))',
        ),
        isTrue,
      );
      expect(
        executeExpression(
          {'test': 'why hello there'},
          r'and(not(empty(#test)), and(match(#test, "hello"), match(#test, "there")))',
        ),
        isTrue,
      );
    });
  });

  group('concatenation', () {
    test('concatenation returns values and final truthiness', () {
      expect(executeExpression({}, r'concat("test", "123")'), isTrue);
      expect(parseExpression(r'concat("a", "b", "c", "d")').evaluateValue({}),
          'abcd');
      expect(
          parseExpression(r'concat("a", 0, false, #missing, "b")')
              .evaluateValue({}),
          'ab');
      expect(executeExpression({}, 'concat(#1, #2)'), isFalse);
      expect(executeExpression({'1': '123'}, 'concat(#1, #2)'), isTrue);
    });

    test('concatenation supports composed regex patterns', () {
      expect(
        executeExpression(
          {'pattern': 'hello there', 'test': 'hello there'},
          r'match(#test, concat(concat("^", #pattern), "$"))',
        ),
        isTrue,
      );
      expect(
        executeExpression(
          {'pattern1': 'hello', 'pattern2': 'there', 'test': 'hello there'},
          r'and( match(#test, concat("^", #pattern1)), match(#test, concat(#pattern2, "$")) )',
        ),
        isTrue,
      );
      expect(
        executeExpression(
          {'pattern1': 'hello', 'pattern2': 'there', 'test': 'hello there'},
          r'match(#test, concat(concat(concat(concat("(", #pattern1), ")(?! "), #pattern2), ")"))',
        ),
        isFalse,
      );
      expect(
        executeExpression(
          {
            'pattern1': 'hello',
            'pattern2': 'there',
            'test': 'hello over there'
          },
          r'match(#test, concat(concat(concat(concat("(", #pattern1), ")(?! "), #pattern2), ")"))',
        ),
        isTrue,
      );
    });
  });

  group('length', () {
    test('can test input lengths', () {
      expect(
          executeExpression({'test': 'hello'}, 'lt(len(#test), 10)'), isTrue);
      expect(
          executeExpression({'test': 'hello'}, 'gt(len(#test), 10)'), isFalse);
      expect(executeExpression({'test': 'hello'}, 'eq(len(#test), 5)'), isTrue);
      expect(executeExpression({'test': 'hello'}, 'len(#test)'), isTrue);
      expect(executeExpression({'test': ''}, 'len(#test)'), isFalse);
      expect(executeExpression({'test': ''}, 'eq(len(#test), 0)'), isTrue);
      expect(executeExpression({}, 'len(#test)'), isFalse);
      expect(executeExpression({}, 'eq(len(#test), 0)'), isTrue);
      expect(executeExpression({}, r'eq(len("test"), 2)'), isFalse);
      expect(executeExpression({}, r'eq(len("test"), 4)'), isTrue);
    });
  });

  group('model references and logical evaluation', () {
    test('nested model references are resolved without flattening', () {
      expect(
        executeExpression(
          {
            'form': {
              'address': {'city': 'Ghent'}
            }
          },
          r'eq(#form.address.city, "Ghent")',
        ),
        isTrue,
      );
      expect(
        executeExpression({'form.address.city': 'literal'},
            r'eq(#form.address.city, "literal")'),
        isTrue,
      );
      expect(
          executeExpression({'form': {}}, 'empty(#form.address.city)'), isTrue);
    });

    test('and and or short-circuit the right operand', () {
      final model = {'value': <String, Object?>{}};
      expect(() => executeExpression(model, 'len(#value)'), throwsStateError);
      expect(executeExpression(model, 'and(false, len(#value))'), isFalse);
      expect(executeExpression(model, 'or(true, len(#value))'), isTrue);
    });

    test('and and or short-circuit later operands', () {
      final model = {'value': <String, Object?>{}};
      expect(executeExpression(model, 'and(true, true, false, len(#value))'),
          isFalse);
      expect(executeExpression(model, 'or(false, false, true, len(#value))'),
          isTrue);
    });

    test('or evaluates a truthy or falsey right operand when needed', () {
      expect(executeExpression({}, r'or(false, "value")'), isTrue);
      expect(executeExpression({}, 'or(false, 0)'), isFalse);
    });
  });

  group('malformed expressions', () {
    test('malformed expressions are rejected', () {
      for (final expression in [
        'eq(1foo, 1)',
        'eq(1, 2, 3)',
        'not(true, false)',
        'eq(1, 2) trailing',
        'eq((1), 1)',
      ]) {
        expect(() => executeExpression({}, expression), throwsException);
      }
    });
  });

  group('operators', () {
    test('contains is case-sensitive and only accepts string input', () {
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'contains(#value, "world")'),
          isTrue);
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'contains(#value, "World")'),
          isFalse);
      expect(executeExpression({'value': 12345}, r'contains(#value, "23")'),
          isFalse);
    });

    test('in checks list membership using loose equality', () {
      expect(executeExpression({}, r'''in("test", ["yes", 'no'])'''), isFalse);
      expect(executeExpression({}, r'in("yes", [ "yes" , "no" ] )'), isTrue);
      expect(executeExpression({}, r'in(1, ["1", 2])'), isTrue);
      expect(executeExpression({}, r'in(false, [0, true])'), isTrue);
      expect(executeExpression({}, r'in("yes", [])'), isFalse);
      expect(executeExpression({}, r'in("yes", "yes")'), isFalse);
      expect(
        executeExpression({
          'value': 'yes',
          'allowed': ['yes', 'no']
        }, 'IN(#value, #allowed)'),
        isTrue,
      );
    });

    test('lists evaluate expressions and model references', () {
      expect(
        parseExpression(r'[1, lower("YES"), [true, 2]]').evaluateValue({}),
        [
          1.0,
          'yes',
          [true, 2.0]
        ],
      );
      expect(
        executeExpression(
            {'value': 'yes'}, r'in(#value, [lower("YES"), #other])'),
        isTrue,
      );
      expect(
        executeExpression(
          {'value': 'no', 'other': 'yes'},
          r'in(#value, [lower("YES"), #other])',
        ),
        isFalse,
      );
    });

    test('startswith and endswith are case-sensitive and string-only', () {
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'startswith(#value, "Hello")'),
          isTrue);
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'startswith(#value, "hello")'),
          isFalse);
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'endswith(#value, "world")'),
          isTrue);
      expect(
          executeExpression(
              {'value': 'Hello world'}, r'endswith(#value, "World")'),
          isFalse);
      expect(executeExpression({'value': 12345}, r'startswith(#value, "12")'),
          isFalse);
      expect(executeExpression({'value': 12345}, r'endswith(#value, "45")'),
          isFalse);
    });

    test('lower and upper coerce values to strings', () {
      expect(parseExpression(r'lower("Hello WORLD")').evaluateValue({}),
          'hello world');
      expect(parseExpression(r'upper("Hello world")').evaluateValue({}),
          'HELLO WORLD');
      expect(parseExpression('lower(123)').evaluateValue({}), '123');
      expect(parseExpression('upper(true)').evaluateValue({}), 'TRUE');
      expect(parseExpression('lower(0)').evaluateValue({}), '');
      expect(parseExpression('upper(false)').evaluateValue({}), '');
      expect(parseExpression('lower(#missing)').evaluateValue({}), '');
    });

    test('trim preserves nullish values and trims text', () {
      expect(parseExpression(r'trim("  hello world  ")').evaluateValue({}),
          'hello world');
      expect(parseExpression(r'trim("hello  world")').evaluateValue({}),
          'hello  world');
      expect(parseExpression('trim(123)').evaluateValue({}), '123');
      expect(parseExpression('trim(false)').evaluateValue({}), '');
      expect(parseExpression('trim(0)').evaluateValue({}), '');
      expect(
          parseExpression('trim(#null)').evaluateValue({'null': null}), isNull);
      expect(parseExpression('trim(#missing)').evaluateValue({}), isNull);
    });

    test('defined distinguishes nullish from other falsey values', () {
      expect(executeExpression({}, r'defined("")'), isTrue);
      expect(executeExpression({}, 'defined(0)'), isTrue);
      expect(executeExpression({}, 'defined(false)'), isTrue);
      expect(executeExpression({}, 'defined([])'), isTrue);
      expect(executeExpression({'null': null}, 'defined(#null)'), isFalse);
      expect(executeExpression({}, 'defined(#missing)'), isFalse);
    });

    test('defined and trim are case-insensitive', () {
      expect(parseExpression(r'TRIM("  value  ")').evaluateValue({}), 'value');
      expect(executeExpression({'null': null}, 'DEFINED(#null)'), isFalse);
    });

    test('if evaluates only the selected branch and preserves its value', () {
      expect(
          parseExpression(r'if(true, "yes", len(#value))')
              .evaluateValue({'value': {}}),
          'yes');
      expect(
          parseExpression(r'if(false, len(#value), "no")')
              .evaluateValue({'value': {}}),
          'no');
      expect(executeExpression({}, 'if(eq(1, 1), 0, 1)'), isFalse);
    });

    test('new operators are case-insensitive', () {
      expect(executeExpression({}, r'STARTSWITH("Hello", "He")'), isTrue);
      expect(executeExpression({}, r'ENDSWITH("Hello", "lo")'), isTrue);
      expect(parseExpression(r'LOWER("Hello")').evaluateValue({}), 'hello');
      expect(parseExpression(r'UPPER("Hello")').evaluateValue({}), 'HELLO');
      expect(
          parseExpression(r'IF(true, "yes", "no")').evaluateValue({}), 'yes');
    });

    test('comparison operators preserve loose equality and ordering', () {
      expect(executeExpression({}, r'eq(1, "1")'), isTrue);
      expect(executeExpression({}, 'eq(false, 0)'), isTrue);
      expect(executeExpression({}, 'gt(10, 2)'), isTrue);
      expect(executeExpression({}, r'lt("a", "b")'), isTrue);
      expect(executeExpression({}, 'gt(2, 2)'), isFalse);
      expect(executeExpression({}, 'lt(2, 2)'), isFalse);
    });

    test('empty distinguishes falsey values from empty values', () {
      expect(executeExpression({'value': null}, 'empty(#value)'), isTrue);
      expect(executeExpression({}, 'empty(#value)'), isTrue);
      expect(executeExpression({'value': ''}, 'empty(#value)'), isTrue);
      expect(executeExpression({'value': 0}, 'empty(#value)'), isFalse);
      expect(executeExpression({'value': false}, 'empty(#value)'), isFalse);
      expect(executeExpression({'value': []}, 'empty(#value)'), isFalse);
      expect(executeExpression({'value': {}}, 'empty(#value)'), isFalse);
    });

    test('len supports strings, arrays, and own length properties', () {
      expect(
          executeExpression({
            'value': [1, 2, 3]
          }, 'eq(len(#value), 3)'),
          isTrue);
      expect(
          executeExpression({
            'value': {'length': 4}
          }, 'eq(len(#value), 4)'),
          isTrue);
      expect(
        () => executeExpression({'value': {}}, 'len(#value)'),
        throwsA(isA<StateError>()),
      );
      expect(executeExpression({'value': 'value'}, 'len(#value)'), isTrue);
    });

    test('concat stringifies truthy values and ignores falsey values', () {
      expect(
          parseExpression(r'concat("value", 12)').evaluateValue({}), 'value12');
      expect(parseExpression('concat(0, false)').evaluateValue({}), '');
      expect(parseExpression(r'concat(#missing, "value")').evaluateValue({}),
          'value');
      expect(
          parseExpression('concat(true, #value)').evaluateValue({'value': 5}),
          'true5');
    });
  });

  group('numbers and strings', () {
    test('accepts signed, decimal, and exponent numeric literals', () {
      expect(parseExpression('+12').evaluateValue({}), 12.0);
      expect(parseExpression('-.5').evaluateValue({}), -0.5);
      expect(parseExpression('1.').evaluateValue({}), 1.0);
      expect(parseExpression('1e3').evaluateValue({}), 1000.0);
      expect(parseExpression('-2.5E-2').evaluateValue({}), -0.025);
      expect(parseExpression('-0').evaluateValue({}), 0.0);
    });

    test('accepts all supported quoted string delimiters', () {
      expect(parseExpression(r'"double"').evaluateValue({}), 'double');
      expect(parseExpression("'single'").evaluateValue({}), 'single');
      expect(parseExpression('`backtick`').evaluateValue({}), 'backtick');
    });

    test('rejects malformed numeric-like tokens and bare identifiers', () {
      expect(() => parseExpression('1foo'), throwsException);
      expect(() => parseExpression('foo1'), throwsException);
      expect(() => parseExpression('_value'), throwsException);
      expect(
          () => parseExpression('hello'),
          throwsA(
            predicate((error) =>
                error.toString().contains('invalid operator: hello')),
          ));
    });
  });

  group('dynamic regular expressions', () {
    test('accepts a pattern from the model and evaluates it per model', () {
      final expression = parseExpression('match(#value, #pattern)');
      expect(
          expression.evaluateValue({'value': 'hello', 'pattern': r'^hello$'}),
          isTrue);
      expect(
          expression.evaluateValue({'value': 'goodbye', 'pattern': r'^hello$'}),
          isFalse);
    });

    test('returns false for empty or non-string patterns', () {
      expect(
          executeExpression(
              {'value': 'hello', 'pattern': ''}, 'match(#value, #pattern)'),
          isFalse);
      expect(
          executeExpression(
              {'value': 'hello', 'pattern': 123}, 'match(#value, #pattern)'),
          isFalse);
      expect(
          executeExpression({'value': 'hello'}, 'match(#value, 0)'), isFalse);
    });

    test('converts falsey input values to an empty regex input', () {
      const expression = r'match(#value, ".{0}")';
      expect(executeExpression({'value': 0}, expression), isTrue);
      expect(executeExpression({'value': false}, expression), isTrue);
      expect(executeExpression({'value': null}, expression), isTrue);
      expect(executeExpression({}, expression), isTrue);
    });

    test('rejects invalid constant and runtime patterns', () {
      expect(() => parseExpression(r'match("value", "[")'), throwsException);
      final expression = parseExpression('match(#value, #pattern)');
      expect(
        () => expression.evaluateValue({'value': 'value', 'pattern': '['}),
        throwsException,
      );
    });

    test('reuses a constant pattern for repeated evaluations', () {
      final expression = parseExpression(r'match(#value, "hello")');
      expect(expression.evaluateValue({'value': 'hello'}), isTrue);
      expect(expression.evaluateValue({'value': 'goodbye'}), isFalse);
      expect(expression.evaluateValue({'value': 'hello again'}), isTrue);
    });
  });

  group('model references', () {
    test('handles null models and null intermediate properties', () {
      expect(executeExpression(null, 'empty(#value)'), isTrue);
      expect(executeExpression({'value': null}, 'empty(#value.child)'), isTrue);
      expect(
          executeExpression({
            'value': {'child': null}
          }, 'empty(#value.child)'),
          isTrue);
    });

    test('prefers an exact dotted key over nested traversal', () {
      final expression = parseExpression('#value.child');
      expect(
        expression.evaluateValue({
          'value': {'child': 'nested'},
          'value.child': 'direct'
        }),
        'direct',
      );
      expect(
        expression.evaluateValue({
          'value': {'child': 'nested'},
          'value.child': null
        }),
        isNull,
      );
    });

    test('only resolves Map properties', () {
      expect(parseExpression('#value').evaluateValue(Object()), isNull);
      expect(parseExpression('#value.child').evaluateValue({'value': Object()}),
          isNull);
    });

    test('rejects prototype-chain reference segments', () {
      for (final expression in [
        '#__proto__',
        '#value.constructor',
        '#value.prototype.name',
      ]) {
        expect(() => parseExpression(expression), throwsException);
      }
    });

    test('rejects empty or malformed model references', () {
      for (final expression in ['#', '#.value', '#value.', '#value..child']) {
        expect(() => parseExpression(expression), throwsException);
      }
    });
  });

  group('parser validation', () {
    test('rejects every malformed expression from the TypeScript suite', () {
      for (final expression in [
        '',
        '   ',
        'not()',
        'eq(1)',
        'eq(1,)',
        'eq(,1)',
        'and(true)',
        'or(false)',
        'concat("value")',
        'eq(1 2)',
        'eq(1, 2',
        'eq(1, 2))',
        'xor(true, false)',
        'lower("value", "extra")',
        'startswith("value")',
        'if(true, 1)',
        'if(true, 1, 2, 3)',
        '[1,]',
        '[1 2]',
        '[1, 2',
        'eq(1, 2)\ttrailing',
      ]) {
        expect(() => executeExpression({}, expression), throwsException);
      }
    });

    test('rejects unsupported constructor input and unterminated strings', () {
      expect(() => Expression(123), throwsArgumentError);
      expect(() => executeExpression({}, 123), throwsArgumentError);
      expect(() => SimpleExpressions.get(123), throwsArgumentError);
      expect(() => parseExpression('"unterminated'), throwsException);
    });
  });
}
